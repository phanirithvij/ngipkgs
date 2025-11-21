{ config, ... }:
{
  sops = {
    # See <https://github.com/Mic92/sops-nix>.
    age.keyFile = "/dev/null"; # For a production configuration, set this option.
    defaultSopsFile = "/dev/null"; # For a production configuration, set this option.
    validateSopsFiles = false; # For a production configuration, remove this line.
    secrets."pdfding/minio/root_creds" = {
      owner = config.services.minio.user;
      group = config.services.minio.group;
      mode = "0440";
    };
    secrets."pdfding/django/secret_key_file" = {
      owner = config.services.pdfding.user;
      group = config.services.pdfding.group;
    };
  };

  services.pdfding = {
    enable = true;
    secretKeyFile = config.sops.secrets."pdfding/django/secret_key_file".path;
  };

  users.users.pdfding.extraGroups = [ config.services.minio.group ]; # allow reading creds

  services.minio = {
    enable = true;
    rootCredentialsFile = config.sops.secrets."pdfding/minio/root_creds".path;
    listenAddress = "127.0.0.1:9000";
    consoleAddress = "127.0.0.1:9001";
  };

  networking.firewall.allowedTCPPorts = [
    9000
    9001
  ];
}
