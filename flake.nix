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
                home = "/var/empty";
                shell = "${pkgs.${system}.util-linux}/bin/nologin";
              };
              users.groups.${user} = { };
              systemd.services = {
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
