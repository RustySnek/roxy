{
  pkgs,
  ...
}:
pkgs.rustPlatform.buildRustPackage {
  pname = "roxy";
  version = "0.1";
  cargoLock.lockFile = ./Cargo.lock;
  src = pkgs.lib.cleanSource ./.;
  nativeBuildInputs = with pkgs; [
    openssl
  ];
}
