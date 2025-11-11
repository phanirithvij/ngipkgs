{
  lib,
  python312,
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
    - [x] django manage.py cli wrapper
    - [ ] pytest tests
    - [ ] server (the nixos module?)
    - [ ] versioncheckhook not possible to add because no cli
  - [ ] nixos module
    - BASE_DIR needs to be patched likely for /var/lib/pdfding/{media,db}
  - [ ] nixos tests
    - [ ] e2e
  - [ ] example
*/
let
  python3 = python312;
  python = python3.override {
    self = python;
    packageOverrides = final: prev: {
      # TODO figure out exact versions for other deps from upstream's poetry lock
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
  ];

  frontend = callPackage ./frontend.nix { };

  pythonPath = python.pkgs.makePythonPath pythonPackages;
in

python.pkgs.buildPythonApplication rec {
  pname = "pdfding";

  # TODO pyproject.toml still has 0.1.1 very old version, pr a fix upstream or patch?
  #version = "1.3.3";
  version = "1.4.0";
  src = fetchFromGitHub {
    owner = "mrmn2";
    repo = "PdfDing";
    tag = "v${version}";
    #hash = "sha256-TRQQdZa4X+Kx13QCYChqkN4eT5VJjAti+DR+MqOPsOU="; # v1.3.3
    hash = "sha256-G2Dzszuau3Z//0ClOJLeuatLZSJBj1uTBJfWt0/x3to="; # v1.4.0
  };
  pyproject = true;

  dependencies = pythonPackages;

  build-system = with python.pkgs; [ poetry-core ];

  nativeBuildInputs = [
    makeWrapper
  ];

  preBuild = ''
    # remove originals, copy from frontend
    rm -rf pdfding/static
    ln -s ${passthru.frontend}/pdfding/static pdfding/static

    # TODO slow step, disabling temporarily for quick iterations
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

    echo "VERSION = '${version}'" > pdfding/core/settings/version.py;
  '';

  postInstall = ''
    mkdir -p $out/bin

    # prod build, as per dockerfile
    rm pdfding/core/settings/dev.py

    makeWrapper "$out/${python.sitePackages}/pdfding/manage.py" $out/bin/pdfding-manage \
      --prefix PYTHONPATH : "${pythonPath}"
  '';

  # TODO too many mismatched deps from project's requirements, and no better solution
  # if some dep doesn't work it needs to be manually overriden via python3.override, packageOverrides
  # Or poetry2nix (remember it being abandoned) maybe magic2nix which ngipkgs already seems to import
  # focus is to make it work in nixpkgs, ie. no 2nix. and 2nix as a last resort
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

  nativeCheckInputs = with python.pkgs; [
    pillow
    pytest-cov-stub
    pytest-django
    pytestCheckHook
  ];

  #TODO disable this for quick iteration as well
  #doCheck = false;

  # from .github/workflows/tests.yaml
  pytestFlags = [
    "--ignore=e2e"
    "--cov=admin"
    "--cov=backup"
    "--cov=base"
    "--cov=pdf"
    "--cov=users"
    "--cov-fail-under=100"
  ];

  /*
     fix two breaking tests by providing full out path
     AssertionError: Calls not found
     AssertionError: 'add_file_to_minio' does not contain all of ...
  */
  preCheck = ''
    pushd pdfding || exit 1

    substituteInPlace backup/tests/test_management.py backup/tests/test_tasks.py \
      --replace-fail "Path(__file__).parents[2]" "Path('$out/${python.sitePackages}/pdfding')"
  '';

  postCheck = ''
    popd || exit 1
  '';

  # enabledTestPaths = [ "backup/" ]; # TODO remove once fixed/disabled, added for quick iteration

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
    license = lib.licenses.agpl3Only; # TODO is it agpl3Plus
    maintainers = with lib.maintainers; [ phanirithvij ];
    teams = with lib.teams; [ ngi ];
    mainProgram = "pdfding-manage";
  };
}
