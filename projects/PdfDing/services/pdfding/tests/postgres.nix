{
  lib,
  pkgs,
  sources,
  ...
}:
let
  port = 8000;
in
{
  name = "PdfDing default";

  nodes = {
    machine =
      { ... }:
      {
        imports = [
          sources.modules.ngipkgs
          sources.modules.services.pdfding
          sources.examples.PdfDing.basic
          sources.examples.PdfDing.postgres
          "${sources.inputs.sops-nix}/modules/sops"
        ];

        sops = lib.mkForce {
          age.keyFile = "/run/keys.txt";
          defaultSopsFile = ./sops/pdfding.yaml;
        };

        # must run before sops sets up keys
        boot.initrd.postDeviceCommands = ''
          cp -r ${./sops/keys.txt} /run/keys.txt
          chmod -R 700 /run/keys.txt
        '';

        environment.systemPackages = [ pkgs.pdfding ];
        services.pdfding.port = port;
        services.pdfding.consume.enable = true;

        virtualisation.forwardPorts = map (port: {
          from = "host";
          host.port = port;
          guest.port = port;
        }) [ port ];

        # forwarded ports need to be accessible
        networking.firewall.allowedTCPPorts = [ port ];
      };
  };

  # Debug interactively with:
  # - nix run .#checks.x86_64-linux.projects/PdfDing/nixos/tests/basic.driverInteractive -L
  # - start_all() / run_tests()
  interactive.sshBackdoor.enable = true; # ssh -o User=root vsock/3
  interactive.nodes.machine =
    { config, ... }:
    {
      # not needed, only for manual interactive debugging
      virtualisation.memorySize = 4096;
      environment.systemPackages = with pkgs; [
        btop
        sysz
      ];
    };

  # TODO
  # Tests the most basic user functionality expected from pdfding with postgres
  testScript =
    { nodes, ... }:
    # py
    ''
      start_all()
      machine.wait_for_unit("pdfding.service")

      # start
      # create admin
      # create normal user via API?

      # make sample pdf (could be any test file or valid pdf?)
      # upload via API to user
      # download via API to user
      # https://github.com/mrmn2/PdfDing/blob/master/docs/guides.md#consumption-directory
      # make user consume pdfs via admin
      # test if user can access via API
    '';
}
