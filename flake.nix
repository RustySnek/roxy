{
  description = "Roxy HTTPS Proxy";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgs = nixpkgs.legacyPackages;
    in
    {
      packages = forAllSystems (system: rec {
        default = pkgs.${system}.callPackage ./default.nix { };
        nixosModule =
          {
            config,
            lib,
            ...
          }:
          let
            cfg = config.services.roxy;
            user = "roxy-proxy";
          in
          {
            options.services.roxy = {
              enable = lib.mkEnableOption "roxy";
              remote = lib.mkOption {
                type = lib.types.str;
                description = "Allowed Singular Remote IP. example: 127.0.0.1";
              };
              port = lib.mkOption {
                type = lib.types.str;
                default = "8080";
                description = "Service Port";
              };
              remote-port = lib.mkOption {
                type = lib.types.str;
                default = "4445";
                description = "Remote machine port";
              };
              remote-user = lib.mkOption {
                type = lib.types.str;
                description = "Remote user";
              };
              hosts = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                example = [
                  "google.com"
                  "example.com"
                ];
              };
            };
            config = lib.mkIf cfg.enable {
              environment.systemPackages = [ default ];
              users.users.${user} = {
                isSystemUser = true;
                group = user;
                createHome = true;
                home = "/var/lib/${user}";
                packages = [ pkgs.${system}.openssh ];
                shell = "${pkgs.${system}.bash}/bin/bash";
              };
              users.groups.${user} = { };
              systemd.services = {
                roxy-tunnel-setup = {
                  description = "Setup SSH directory for roxy tunnel";
                  before = [ "roxy-tunnel.service" ];
                  wantedBy = [ "roxy-tunnel.service" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = "yes";
                    User = user;
                  };
                  script = ''
                    mkdir -p /var/lib/${user}/.ssh
                    chmod 700 /var/lib/${user}/.ssh
                    for key in id_ecdsa id_ecdsa_sk id_ed25519 id_ed25519_sk id_xmss; do
                      if [ ! -f /var/lib/${user}/.ssh/$key ]; then
                        ${pkgs.${system}.openssh}/bin/ssh-keygen -t ecdsa -f /var/lib/${user}/.ssh/$key -N "" -C "roxy-tunnel"
                      fi
                        chmod 600 /var/lib/${user}/.ssh/$key
                      done
                    touch /var/lib/${user}/.ssh/known_hosts
                    chmod 600 /var/lib/${user}/.ssh/known_hosts
                    ${pkgs.${system}.openssh}/bin/ssh-keyscan -H ${cfg.remote} >> /var/lib/${user}/.ssh/known_hosts
                  '';
                };
                roxy-tunnel = {
                  wantedBy = [ "multi-user.target" ];
                  bindsTo = [ "roxy.service" ];
                  after = [ "roxy.service" ];
                  description = "Start up roxy ssh reverse tunnel";
                  serviceConfig = {
                    User = user;
                    Group = user;
                  };
                  script = ''
                    ${pkgs.${system}.openssh}/bin/ssh -v -N -R ${cfg.remote-port}:127.0.0.1:${cfg.port} ${cfg.remote-user}@${cfg.remote}
                  '';
                };

                roxy = {
                  description = "Start up https proxy";
                  environment = {
                    ALLOWED_REMOTE = cfg.remote;
                    PORT = cfg.port;
                    ALLOWED_HOSTS = lib.strings.concatStringsSep "," cfg.hosts;
                  };
                  script = ''
                    ${default}/bin/roxy 
                  '';

                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    User = user;
                    Group = user;
                  };

                };

              };
            };
          };
      });
    };
}
