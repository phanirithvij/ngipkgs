{
  lib,
  python3,
  callPackage,
  fetchFromGitHub,
  fetchpatch2,
  makeWrapper,
}:
/*
  - pretalx seems to be a django application in ngipkgs
  - paperless-ngx
  - glitchtip
  - package
    - [x] frontend
    - [x] django manage.py cli wrapper
    - [x] pytest tests
    - [x] server (gunicorn)
    - [ ] updateScript
  - [ ] nixos module
    - [x] BASE_DIR needs to be patched likely for /var/lib/pdfding/{media,db}
  - [ ] nixos tests
    - [ ] pytest e2e tests, playwright
      - [ ] versioncheckhook not possible to add because no cli
        - [ ] do some curl version check
    - [ ] sqlite (no huey, no pgsql)
    - [ ] default (pgsql, consume+huey yes)
    - [ ] backups (pgsql, bkp+huey+redis yes)
  - [ ] examples
    - [ ] copy from nixos tests the configs for basic (sqlite), default (posgtgres), full (pg, minio, no-redis huey)
  - [ ] demo vm
    - [ ] 3 vms sqlite, default, full, same as above?
*/
let
  python = python3.override {
    self = python;
    packageOverrides = final: prev: {
      # TODO figure out exact versions for other deps from upstream's poetry lock
      django = prev.django_5_2;
    };
  };

  dependencies = with python.pkgs; [
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
    huey
    supervisor # required but not used by the module, using systemd instead
    pillow
    oauthlib

    # dependecies required for django collectstatic
    requests
    pyjwt
    cryptography
  ];

  frontend = callPackage ./frontend.nix { };
in

python.pkgs.buildPythonApplication rec {
  pname = "pdfding";
  version = "1.4.1";
  src = fetchFromGitHub {
    owner = "mrmn2";
    repo = "PdfDing";
    tag = "v${version}";
    hash = "sha256-8e80gMdB6U3977dIU7bIAAEguYmi+AWQgUgYPDLCYLI=";
  };
  pyproject = true;

  patches = [
    # remove in 1.4.2 (next version after 1.4.1)
    # patch to add data_dir
    # https://github.com/mrmn2/PdfDing/pull/202
    (fetchpatch2 {
      url = "https://github.com/mrmn2/PdfDing/commit/387ca2079f74844203e2e91fac00e0d0e0e5fdb9.patch?full_index=1";
      hash = "sha256-VGjyIAVi+qd2WZ8FVKKC2ijLinoflO7RmPwIW1/oGcY=";
    })
    # pyproject.toml still has 0.1.1 very old version
    # follow https://github.com/mrmn2/PdfDing/pull/203
    ./add-version.patch
  ];

  inherit dependencies;

  build-system = with python.pkgs; [ poetry-core ];

  nativeBuildInputs = [
    makeWrapper
  ];

  preBuild = ''
    # remove originals, copy from frontend
    rm -rf pdfding/static
    ln -s ${passthru.frontend}/pdfding/static pdfding/static

    # not generating staticfiles.json if it exists
    mv pdfding/core/settings/dev.py pdfding/core/settings/dev.py.bak

    ${python.pythonOnBuildForHost.interpreter} pdfding/manage.py collectstatic

    # dev.py is required so that test will run properly, restore it
    mv pdfding/core/settings/dev.py.bak pdfding/core/settings/dev.py

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
    pdfdingDir=$out/${python.sitePackages}/pdfding
    pythonPath=${python.pkgs.makePythonPath dependencies}

    # make an empty dir to supress the warning
    mkdir -p $pdfdingDir/static

    makeWrapper "$pdfdingDir/manage.py" $out/bin/pdfding-manage \
      --set-default DATA_DIR "/var/lib/pdfding" \
      --prefix PYTHONPATH : "$pythonPath"

    makeWrapper ${lib.getExe python.pkgs.gunicorn} $out/bin/pdfding-start \
      --set-default DATA_DIR "/var/lib/pdfding" \
      --prefix PYTHONPATH : "$pythonPath:$pdfdingDir" \
      --add-flags '--bind ''${HOST_IP:-127.0.0.1}:''${HOST_PORT:-8080} core.wsgi:application'
  '';

  # TODO too many mismatched deps from project's requirements, and no better solution
  # if some dep doesn't work it needs to be manually overriden via python3.override, packageOverrides
  # Or poetry2nix (remember it being abandoned) maybe magic2nix which ngipkgs already seems to import
  # the focus is to make it work in nixpkgs, ie. no 2nix, and 2nix as a last resort
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

  # dev.py is required for tests and MUST be removed from the final output
  # this could be done in postCheck, but doing it here will allow doCheck to be toggleable
  postPhases = [ "finalPhase" ];

  finalPhase = ''
    # dev.py should be removed on production build (source Dockerfile)
    # can't be removed earlier, required for checkPhase
    rm $out/${python.sitePackages}/pdfding/core/settings/dev.py
  '';

  # enabledTestPaths = [ "backup/" ]; # TODO remove once fixed/disabled, added for quick iteration

  pythonImportsCheck = [
    "pdfding"
  ];

  passthru = {
    updateScript = ./update.sh;
    inherit frontend;
  };

  meta = {
    description = "Selfhosted PDF manager, viewer and editor offering a seamless user experience on multiple devices";
    homepage = "https://github.com/mrmn2/PdfDing";
    changelog = "https://github.com/mrmn2/PdfDing/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ phanirithvij ];
    teams = with lib.teams; [ ngi ];
    mainProgram = "pdfding-manage";
  };
}
