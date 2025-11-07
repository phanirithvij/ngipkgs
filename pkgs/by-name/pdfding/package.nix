{
  lib,
  fetchzip,
  fetchFromGitHub,
  stdenv,
  python3,

  nodejs,
  npmHooks,
  fetchNpmDeps,
  tailwindcss_4,
  moreutils,
  jq,
}:
/*
  - package
    - [x] frontend
    - [ ] server
    - [ ] django manage cli wrapper
  - [ ] nixos module
  - [ ] nixos test
  - [ ] example
*/
let
  version = "1.3.3";
  src = fetchFromGitHub {
    owner = "mrmn2";
    repo = "PdfDing";
    tag = "v${version}";
    hash = "sha256-TRQQdZa4X+Kx13QCYChqkN4eT5VJjAti+DR+MqOPsOU=";
  };
  frontend = stdenv.mkDerivation {
    pname = "pdfding-frontend";
    inherit version src;

    npmDeps = fetchNpmDeps {
      inherit src;
      name = "pdfding-frontend-${version}-npm-deps";
      hash = "sha256-m9zr6+3LHG40dDFfTBXwqHCJVyTGuurNJq7xRrosFlA=";
    };

    # npm error Invalid package, must have name and version
    postPatch = ''
      ${lib.getExe jq} '. += { "name": "pdfding-frontend", "version": "${version}" }' package.json \
         | ${lib.getExe' moreutils "sponge"} package.json
    '';

    # TODO pdfjs comes with js source maps, should they be removed in postFetch?
    pdfjs =
      let
        # version from pdfding dockerfile
        # TODO handle in updateScript
        pdfjsVersion = "5.4.149";
      in
      fetchzip {
        url = "https://github.com/mozilla/pdf.js/releases/download/v${pdfjsVersion}/pdfjs-${pdfjsVersion}-dist.zip";
        hash = "sha256-f/wdLva8bsMwcETlT1LiFblbOXbDAOFOiPvpJ6Ziysk=";
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
  };
  python = python3.override {
    self = python;
    packageOverrides = final: prev: {
      # TODO figure out exact versions from upstream's docker runtime or poetry lock
      django = prev.django_5_2;
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "pdfding";
  inherit version src;
  pyproject = true;

  build-system = with python.pkgs; [ poetry-core ];

  dependencies = with python.pkgs; [
    django
    django-allauth
    django-cleanup
    django-htmx
    gunicorn
    huey # TODO what's run_huey in django
    markdown
    minio # TODO is it still foss?
    nh3
    psycopg2-binary
    pypdf
    pypdfium2
    python-magic
    qrcode
    rapidfuzz
    ruamel-yaml
    supervisor # TODO what about this? does it work with systemd service?
    whitenoise
  ];

  preBuild = ''
    # prod build, as per dockerfile
    rm pdfding/core/settings/dev.py

    rm -rf pdfding/static
    # can't do symlinking because python package doesn't allow it
    cp -r --no-preserve=mode ${passthru.frontend}/pdfding/static pdfding/static
  '';

  # TODO too many mismatched deps from project's requirements, and no better solution
  # if some dep doesn't work it needs to be manually overriden via python3.override, packageOverrides
  pythonRelaxDeps = true;
  /*
    pythonRelaxDeps = [
      "django"
      "django-allauth"
      "django-htmx"
      "minio"
      "nh3"
      "pypdf"
      "pypdfium2"
      "ruamel-yaml"
    ];
  */

  pythonImportsCheck = [
    "pdfding"
  ];

  passthru = {
    updateScript = ""; # TODO custom update script maybe, for handling npmDeps hash
    inherit frontend; # would allow easily overriding it
  };

  meta = {
    description = "Selfhosted PDF manager, viewer and editor offering a seamless user experience on multiple devices";
    homepage = "https://github.com/mrmn2/PdfDing";
    changelog = "https://github.com/mrmn2/PdfDing/blob/${src.tag}/CHANGELOG.md";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ phanirithvij ];
    teams = with lib.teams; [ ngi ];
    mainProgram = "pdfding";
  };
}
