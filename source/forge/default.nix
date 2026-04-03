{
  pkgs,
  mkWebuiDistrib,
  ...
}: let
  raw = pkgs.callPackage ./raw.nix {};

  createPackage = import ./package.nix;
in {
  cuda = mkWebuiDistrib {
    source = raw;
    python = pkgs.python311;

    additionalRequirements =
      raw.additionalRequirements
      ++ [
        # Acceleration on CUDA
        {
          name = "xformers";
          spec = "0.0.27";
        }
      ];

    installInstructions = ./install-instructions-cuda.json;

    inherit createPackage;
  };

  rocm = mkWebuiDistrib {
    source = raw;
    python = pkgs.python311;
    # Filter out bitsandbytes for ROCm - it expects CUDA and causes import issues
    additionalRequirements =
      (builtins.filter (r: r.name != "bitsandbytes") raw.additionalRequirements)
      ++ [
        # AI-NOTE: PyTorch 2.11.0 with ROCm 7.2 - matches nixpkgs ROCm 7.2.1 system libs
        {
          name = "torch";
          spec = "2.11.0+rocm7.2";
        }
        {
          name = "torchvision";
          spec = "0.26.0+rocm7.2";
        }
      ];
    additionalPipArgs = ["--extra-index-url" "https://download.pytorch.org/whl/rocm7.2/"];

    installInstructions = ./install-instructions-rocm.json;

    # createPackage = throw "ROCm is currently broken";
    inherit createPackage; # Want to work on ROCm? Swap the line above with this
  };
}
