{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.pdfding;
in
{
  options.services.pdfding = {
    enable = lib.mkEnableOption "pdfding";
    # TODO check if this makes sense for ngipkgs
    # original comment in the template says leave it if your package is not in nixpkgs
    package = lib.mkPackageOption pkgs "pdfding" { };
  };
  config = lib.mkIf cfg.enable {
    # TODO systemd service based on some existing django service in nixpkgs
    # It should allow managing via manage.py
  };
}
