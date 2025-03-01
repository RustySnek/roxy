use std::{error::Error, net::Ipv4Addr, str::FromStr, sync::Arc};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::Semaphore,
};

fn parse_connect_request(request: &str) -> Result<String, Box<dyn Error + Send + Sync>> {
    let first_line = request.lines().next().ok_or("Empty request")?;
    let parts: Vec<&str> = first_line.split_whitespace().collect();
    if parts.len() < 2 || parts[0] != "CONNECT" {
        return Err(format!("Invalid CONNECT request {request}").into());
    }
    Ok(parts[1].to_string())
}

async fn proxy_data(client: &mut TcpStream, server: &mut TcpStream) -> Result<(), Box<dyn Error>> {
    let (mut client_read, mut client_write) = client.split();
    let (mut server_read, mut server_write) = server.split();

    tokio::select! {
        result = tokio::io::copy(&mut client_read, &mut server_write) => {
            if let Err(e) = result {
                println!("Error copying client to server: {}", e);
            }
        }
        result = tokio::io::copy(&mut server_read, &mut client_write) => {
            if let Err(e) = result {
                println!("Error copying server to client: {}", e);
            }
        }
    }
    Ok(())
}

async fn handle_client(
    mut client: TcpStream,
    allowed_hosts: Arc<Vec<String>>,
) -> Result<(), Box<dyn Error>> {
    let mut buffer = vec![0; 1024];
    let n = client.read(&mut buffer).await?;

    match parse_connect_request(&String::from_utf8_lossy(&buffer[..n])) {
        Ok(host) => {
            let (hostname, _port) = host.split_once(':').unwrap();
            if !allowed_hosts.contains(&hostname.to_string()) {
                println!("Disallowed hostname detected. {host:?}");
                std::process::exit(1);
            }
            println!("Establishing connection to {}", host);
            let mut server = TcpStream::connect(&host).await?;
            println!("Connected to {}", host);

            // Send connection established response
            client
                .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                .await?;

            // Start proxying data
            proxy_data(&mut client, &mut server).await?;
        }
        Err(e) => println!("{e:?}"),
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let ALLOWED_REMOTE: &str = &std::env::var("ALLOWED_REMOTE").unwrap();
    let PORT: &str = &std::env::var("PORT").unwrap();
    let ALLOWED_HOSTS: String = std::env::var("ALLOWED_HOSTS").unwrap();

    let allowed_hosts: Arc<Vec<String>> = Arc::new(
        ALLOWED_HOSTS
            .split_terminator(',')
            .map(|x| x.to_string())
            .collect(),
    );
    let allowed_remote = Ipv4Addr::from_str(ALLOWED_REMOTE).unwrap();

    let listener = TcpListener::bind(format!("127.0.0.1:{PORT}")).await?;

    let semaphore = Arc::new(Semaphore::new(16));

    println!(
        "Proxy server listening on 127.0.0.1:{PORT}\nAllowed remote: {allowed_remote:?}\nAllowed hosts: {allowed_hosts:?}"
    );

    while let Ok((client, addr)) = listener.accept().await {
        if addr.ip().ne(&allowed_remote) {
            panic!("Abnormal remote detected. {client:?} \n {addr:?}");
        };
        println!("New client connection from {}", addr);
        let hosts = allowed_hosts.clone();
        let sem = Arc::clone(&semaphore);
        tokio::spawn(async move {
            let _permit = sem.acquire().await.unwrap();
            if let Err(e) = handle_client(client, hosts).await {
                println!("Error handling client: {:?}", e);
            }
        });
    }
    Ok(())
}
