{
  lib,
  stdenv,
  python313,
  callPackage,
  fetchFromGitHub,
  makeWrapper,
}:
/*
  - pretalx seems to be a django application in ngipkgs
  - paperless-ngx
  - glitchtip
  - package
    - [x] frontend
    - [ ] server
    - [ ] django manage cli wrapper
  - [ ] nixos module
  - [ ] nixos test
  - [ ] example
*/
let
  python3 = python313;
  python = python3.override {
    self = python;
    packageOverrides = final: prev: {
      # TODO figure out exact versions from upstream's docker runtime or poetry lock
      django = prev.django_5_2;
    };
  };

  pythonPackages = with python.pkgs; [
    django
    django-allauth
    django-cleanup
    django-htmx
    gunicorn
    markdown
    minio
    nh3
    psycopg2-binary
    pypdf
    pypdfium2
    python-magic
    qrcode
    rapidfuzz
    ruamel-yaml
    whitenoise

    # collectstatic needs these
    requests
    pyjwt
    cryptography

    huey # TODO what's run_huey in django
    supervisor # TODO what about this? does it work with systemd service?

    poetry-core
  ];

  frontend = callPackage ./frontend.nix { };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "pdfding";
  version = "1.3.3";
  src = fetchFromGitHub {
    owner = "mrmn2";
    repo = "PdfDing";
    tag = "v${finalAttrs.version}";
    hash = "sha256-TRQQdZa4X+Kx13QCYChqkN4eT5VJjAti+DR+MqOPsOU=";
  };
  pyproject = true;

  propagatedBuildInputs = pythonPackages;

  nativeBuildInputs = [
    python
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    # prod build, as per dockerfile
    rm pdfding/core/settings/dev.py

    # remove originals, copy from frontend
    rm -rf pdfding/static
    ln -s ${finalAttrs.passthru.frontend}/pdfding/static pdfding/static

    ${python.pythonOnBuildForHost.interpreter} pdfding/manage.py collectstatic

    # not needed, now we have staticfiles directory
    rm -rf pdfding/static

    # remove django md5 hash from filenames of pdfjs as it will mess up the relative imports because of the whitenoise setup
    sh -x \
        && export PDFJS_PATH="pdfding/staticfiles/pdfjs" \
        && for file_name in $(find $PDFJS_PATH -type f -not -path "$PDFJS_PATH/web/images/*");  \
           do \
                if [[ $file_name =~ "LICENSE" ]]; then \
                  new=$(echo "$file_name" | sed -E "s/LICENSE\.[a-zA-Z0-9]{12}/LICENSE/"); \
                else \
                  new=$(echo "$file_name" | sed -E "s/\.[a-zA-Z0-9]{12}\./\./"); \
                fi; \
                mv -- "$file_name" "$new"; \
           done \
        && echo 'Successfully removed hash from pdfjs files'

    echo "VERSION = '${finalAttrs.version}'" > pdfding/core/settings/version.py;

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    cp -r . $out/lib
    makeWrapper $out/lib/pdfding/manage.py $out/bin/pdfding-manage \
      --prefix PYTHONPATH : "$PYTHONPATH"

    runHook postInstall
  '';

  # TODO too many mismatched deps from project's requirements, and no better solution
  # if some dep doesn't work it needs to be manually overriden via python3.override, packageOverrides
  # pythonRelaxDeps = true;
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

  passthru = {
    updateScript = ""; # TODO custom update script maybe, for handling npmDeps hash
    inherit frontend; # would allow easily overriding it
  };

  meta = {
    description = "Selfhosted PDF manager, viewer and editor offering a seamless user experience on multiple devices";
    homepage = "https://github.com/mrmn2/PdfDing";
    changelog = "https://github.com/mrmn2/PdfDing/blob/${finalAttrs.src.tag}/CHANGELOG.md";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ phanirithvij ];
    teams = with lib.teams; [ ngi ];
    mainProgram = "pdfding-manage";
  };
})
