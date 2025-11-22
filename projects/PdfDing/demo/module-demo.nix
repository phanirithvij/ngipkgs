{
  lib,
  config,
  ...
}:
let
  cfg = config.services.pdfding;
in
{
  config = lib.mkIf cfg.enable {
    # demo mode has some restrictions, it is supposed to be a public instance demo
    # demo for ngipkgs should be a full instance demo without restrictions
    # services.pdfding.extraEnvironment.DEMO_MODE = "TRUE";
    programs.bash.interactiveShellInit = ''
      echo "PdfDing is starting. Please wait ..."
      until systemctl show pdfding.service | grep -q ActiveState=active; do sleep 1; done
      echo "PdfDing is ready at http://localhost:${toString cfg.port}"
    '';
  };
}
