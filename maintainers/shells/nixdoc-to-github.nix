# nix-shell --run nixdoc-to-github
{
  lib,
  busybox,
  gnused,
  stdenv,
  writeShellScriptBin,
  nixdoc-to-github,
}:
let
  genericRunner = nixdoc-to-github.lib.nixdoc-to-github.run {
    description = "PLACEHOLDER_DESC";
    category = "";
    file = "PLACEHOLDER_FILE";
    output = "PLACEHOLDER_OUTFILE";
  };

  template = lib.getExe genericRunner;

  cmd = writeShellScriptBin "nixdoc-to-github" ''
    export PATH="${lib.makeBinPath (if stdenv.isDarwin then [ gnused ] else [ busybox ])}:$PATH"
    outFile="${toString ../docs/project.md}"

    echo "# NGI Project Types" > "$outFile"

    files=(
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
    )

    for f in "''${files[@]}"; do
      name="''${f%.*}"
      real_path="${toString ../types}/$f"
      desc="\\\\\`lib.$name\\\\\`"

      cat "${template}" \
        | sed "s|PLACEHOLDER_FILE|$real_path|g" \
        | sed "s|PLACEHOLDER_DESC|$desc|g" \
        | sed "s|PLACEHOLDER_OUTFILE|/dev/stdout|g" \
        | bash \
        | sed 's/^# `lib.default`$//g' \
        | sed 's/^## .*$/#&/g' \
        | sed 's/^# `lib.*$/#&\n/g' \
        >> "$outFile"

      # remove the extra new line at the end
      head -c -1 "$outFile" >tmp && mv tmp "$outFile"
    done
  '';
in
cmd.overrideAttrs {
  meta.description = "convert nixdoc output to GitHub markdown";
}
