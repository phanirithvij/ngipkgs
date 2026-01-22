# nix-shell --run nixdoc-to-github
{
  lib,
  busybox,
  gnused,
  runCommand,
  stdenv,
  writeShellScriptBin,
  writeText,

  nixdoc-to-github,
}:
let
  getName = file: builtins.head (lib.splitString "." (builtins.baseNameOf file));
  mkDocPart =
    file:
    nixdoc-to-github.lib.nixdoc-to-github.run {
      description = "\\\`lib.${getName file}\\\`";
      category = "";
      inherit file; # copied to store
      output = "\${out:-}";
    };
  docPart =
    file:
    runCommand "docpart-${getName file}"
      {
        nativeBuildInputs = if stdenv.isDarwin then [ gnused ] else [ busybox ];
      }
      ''
        source ${lib.getExe (mkDocPart file)}

        # remove a lib.default header
        sed -i 's/^# `lib.default`$//g' $out

        # decrease h2 to h3
        sed -i 's/^## .*$/#&/g' $out

        # decrease h1 to h2
        sed -i 's/^# `lib.*$/#&\n/g' $out

        # remove extra newline at the end
        head -c -1 $out >tmp && mv tmp $out
      '';
  cmd =
    let
      files = [
        "default.nix"
        "project.nix"
        "metadata.nix"
        "subgrant.nix"
        "link.nix"
        "binary.nix"
        "module.nix"
        "example.nix"
        "demo.nix"
        "test.nix"
      ];
    in
    writeShellScriptBin "nixdoc-to-github" ''
      outFile="${toString ../docs/project.md}"
      echo "# NGI Project Types" >"$outFile"
      ${lib.concatStringsSep "\n" (
        lib.map (file: "cat ${docPart ../types/${file}} >>\"$outFile\"") files
      )}
    '';
in
cmd.overrideAttrs {
  meta.description = "convert nixdoc output to GitHub markdown";
}
