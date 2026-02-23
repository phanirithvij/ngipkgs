{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonPackage (finalAttrs: {
  pname = "bahttext";
  version = "1.0.2-unstable-2020-05-31";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "sekz";
    repo = "bahttext";
    rev = "5dc3a6e9056a81cefb199c49ca69f9a7a9fa835b";
    hash = "sha256-q/z64c5Nqq0PbUGBzyODQchTs2bV9ksujCMLB8ZCB/Y=";
  };

  build-system = [
    python3.pkgs.setuptools
  ];

  pythonImportsCheck = [
    "bahttext"
  ];

  meta = {
    description = "Convert currency number to Thai text number";
    homepage = "https://github.com/sekz/bahttext";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ phanirithvij ];
  };
})
