{
  lib,
  python3,
  fetchFromGitHub,
  bahttext,
}:
python3.pkgs.buildPythonPackage (finalAttrs: {
  pname = "formulas";
  version = "1.3.3";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "vinci1it2000";
    repo = "formulas";
    tag = "v${finalAttrs.version}";
    hash = "sha256-IC8P96VWLqzCLdjUcjEMLLA9rWtdbYW30As1uLKf9dk=";
  };

  build-system = [
    python3.pkgs.setuptools
  ];

  dependencies = with python3.pkgs; [
    schedula
    regex
    numpy
    python-dateutil
    numpy-financial
    scipy
    tqdm
  ];

  optional-dependencies = with python3.pkgs; {
    excel = [
      openpyxl
      dictdiffer
      ezodf
      lxml
    ];
    plot = [
      flask
      regex
      graphviz
      pygments
      jinja2
      docutils
    ];
  };

  checkInputs =
    with python3.pkgs;
    [
      ddt
      dill
      bahttext # WIP upstream to nixpkgs
      pandas
      statsmodels
    ]
    ++ (with finalAttrs.passthru.optional-dependencies; excel ++ plot);

  doCheck = true;
  nativeCheckInputs = with python3.pkgs; [
    #unittestCheckHook
    pytestCheckHook
  ];

  # fix python 3.13 incompatibilities
  postPatch = ''
    substituteInPlace formulas/functions/math.py \
      --replace-warn 'v is 1.0' 'v == 1.0'
    substituteInPlace formulas/functions/stat.py \
      --replace-warn 'v is not ""' 'v != ""'
  '';

  disabledTests = [
    "test_long_description" # not required
  ];

  pythonImportsCheck = [
    "formulas"
  ];

  meta = {
    changelog = "https://github.com/vinci1it2000/formulas/blob/${finalAttrs.src.rev}/CHANGELOG.rst";
    description = "Excel formulas interpreter in Python";
    homepage = "https://github.com/vinci1it2000/formulas";
    license = lib.licenses.eupl11;
    maintainers = with lib.maintainers; [ phanirithvij ];
    teams = with lib.teams; [ ngi ];
  };
})
