{
  pkgs,
  ...
}:
pkgs.rustPlatform.buildRustPackage {
  pname = "roxy";
  version = "0.1";
  cargoLock.lockFile = ./Cargo.lock;
  src = pkgs.lib.cleanSource ./.;
  environment = ''
    PORT=8000
    ALLOWED_HOSTS=example.com
    ALLOWED_REMOTE=127.0.0.1
  '';
  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  buildInputs = with pkgs; [
    openssl
  ];
}
