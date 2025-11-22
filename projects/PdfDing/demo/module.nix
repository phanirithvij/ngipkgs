{ pkgs, ... }:
{
  services.pdfding = {
    enable = true;
    port = 8181; # default is 8000
    secretKeyFile = pkgs.writeText "django_secret" ''
      SECRET_KEY="pdfding-demo-vm"
    '';
  };
  networking.firewall.allowedTCPPorts = [ 8181 ];
}
