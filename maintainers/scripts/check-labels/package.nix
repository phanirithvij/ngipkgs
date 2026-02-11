{ lib
, python3Packages
}:

python3Packages.buildPythonApplication {
  pname = "check-labels";
  version = "0.1.0";
  pyproject = true;

  src = lib.cleanSource ./.;

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
  ];

  propagatedBuildInputs = with python3Packages; [
    requests
    rich
    beautifulsoup4
  ];

  meta = {
    description = "Maintainer tool to sync GitHub labels with NLnet project data";
    mainProgram = "check-labels";
  };
}
