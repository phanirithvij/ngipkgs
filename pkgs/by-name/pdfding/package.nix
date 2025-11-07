{
  lib,
  python3,
  fetchFromGitHub,
  fetchzip,
  buildNpmPackage,
}:
/*
  package
  - frontend
  - django manage cli wrapper
  nixos module
*/
let
  version = "1.3.3";
  src = fetchFromGitHub {
    owner = "mrmn2";
    repo = "PdfDing";
    tag = "v${version}";
    hash = "sha256-TRQQdZa4X+Kx13QCYChqkN4eT5VJjAti+DR+MqOPsOU=";
  };
  frontend = buildNpmPackage {
    pname = "pdfding-frontend";
    inherit version src;
    npmDepsHash = "";

    pdfjs =
      let
        # version from pdfding dockerfile
        # TODO handle in updateScript
        pdfjsVersion = "5.4.296";
      in
      fetchzip {
        url = "https://github.com/mozilla/pdf.js/releases/download/v${pdfjsVersion}/pdfjs-${pdfjsVersion}-dist.zip";
        hash = "sha256-UQ7sYOh7s95mfzH2ZbfDyEvUZiXr7MI3u0WY8WNHWv4=";
        stripRoot = false;
      };
  };
  python = python3.override {
    self = python;
    packageOverrides = final: prev: {
      # TODO figure out exact versions from upstream's docker runtime or poetry lock
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "pdfding";
  inherit version src;
  pyproject = true;

  build-system = with python3.pkgs; [ poetry-core ];

  dependencies = with python3.pkgs; [
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
    ls -l ${passthru.frontend}
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
    updateScript = ""; # TODO custom update script maybe, for handling npmDepsHash
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
