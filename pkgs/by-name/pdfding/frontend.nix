{
  lib,
  stdenv,
  fetchzip,
  fetchFromGitHub,
  nodejs,
  npmHooks,
  fetchNpmDeps,
  tailwindcss_4,
  moreutils,
  jq,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "pdfding-frontend";
  #version = "1.3.3";
  version = "1.4.0";
  src = fetchFromGitHub {
    owner = "mrmn2";
    repo = "PdfDing";
    tag = "v${finalAttrs.version}";
    #hash = "sha256-TRQQdZa4X+Kx13QCYChqkN4eT5VJjAti+DR+MqOPsOU="; # v1.3.3
    hash = "sha256-G2Dzszuau3Z//0ClOJLeuatLZSJBj1uTBJfWt0/x3to="; # v1.4.0
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    name = "pdfding-frontend-${finalAttrs.version}-npm-deps";
    #hash = "sha256-m9zr6+3LHG40dDFfTBXwqHCJVyTGuurNJq7xRrosFlA="; # v1.3.3
    hash = "sha256-v1NFqDnFcRK8sd0bV3ck+LLMYQ90Dl1R1OnBTwWUVUg="; # v1.4.0
  };

  # npm error Invalid package, must have name and version
  postPatch = ''
    ${lib.getExe jq} '. += { "name": "pdfding-frontend", "version": "${finalAttrs.version}" }' package.json \
       | ${lib.getExe' moreutils "sponge"} package.json
  '';

  # TODO pdfjs comes with js source maps, should they be removed in postFetch?
  pdfjs =
    let
      # version from pdfding dockerfile
      # TODO handle in updateScript
      #pdfjsVersion = "5.4.149";
      pdfjsVersion = "5.4.296";
    in
    fetchzip {
      url = "https://github.com/mozilla/pdf.js/releases/download/v${pdfjsVersion}/pdfjs-${pdfjsVersion}-dist.zip";
      #hash = "sha256-f/wdLva8bsMwcETlT1LiFblbOXbDAOFOiPvpJ6Ziysk="; # v1.3.3
      hash = "sha256-UQ7sYOh7s95mfzH2ZbfDyEvUZiXr7MI3u0WY8WNHWv4="; # v1.4.0
      stripRoot = false;
    };

  nativeBuildInputs = [
    nodejs
    npmHooks.npmConfigHook
    # it is in package.json and thus node_modules but no cli executable
    tailwindcss_4
  ];

  # keeping the file structure same as upstream to minimise confusion
  buildPhase = ''
    runHook preBuild
    mkdir -p $out/pdfding
    cp -r --no-preserve=mode pdfding/static $out/pdfding/static
    cp -r --no-preserve=mode $pdfjs $out/pdfding/static/pdfjs

    tailwindcss -i $out/pdfding/static/css/input.css -o $out/pdfding/static/css/tailwind.css --minify
    rm $out/pdfding/static/css/input.css

    for i in build/pdf.mjs build/pdf.sandbox.mjs build/pdf.worker.mjs web/viewer.mjs; \
    do node_modules/terser/bin/terser $out/pdfding/static/pdfjs/$i --compress -o $out/pdfding/static/pdfjs/$i; done

    npm run build

    cp -r pdfding/static/js $out/pdfding/static

    runHook postBuild
  '';
})
