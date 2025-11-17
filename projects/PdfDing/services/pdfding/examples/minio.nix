{ config, ... }:
{
  # backups, consume, huey, huey w/ redis
  services.pdfding = {
    enable = true;
    secretKeyFile = config.sops.secrets."pdfding/django/secret_key".path;
  };
}
