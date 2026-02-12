{
  pkgs ? import <nixpkgs> { },
}:
with pkgs;
buildGoModule {
  pname = "ngi-triage";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  vendorHash = "sha256-yAmydoJZXlipqhZsjojoPA3uoI8BhaU4sPzs9OZ1+3w=";

  nativeBuildInputs = [ makeWrapper ];

  # Runtime dependencies that the Go binary calls via exec.Command
  buildInputs = [
    gh
    nix
    xdg-utils # for xdg-open
  ];

  ldflags = [ "-s" ];

  # This tool expects to run in the root of the repo (to find ./projects and ./default.nix),
  # but we wrap the binary to ensure it can find its tools (gh, nix) no matter what.
  postInstall = ''
    wrapProgram $out/bin/ngi-triage \
      --prefix PATH : ${
        lib.makeBinPath [
          gh
          nix
          xdg-utils
        ]
      }
  '';

  meta = {
    description = "TUI for triaging NGI projects";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
