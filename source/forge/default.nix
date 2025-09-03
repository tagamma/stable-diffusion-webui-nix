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
    additionalRequirements =
      raw.additionalRequirements
      ++ [
        # NOTE: Use stable PyTorch 2.8.0 with ROCm 6.4
        {
          name = "torch";
          spec = "2.8.0+rocm6.4";
        }
        {
          name = "torchvision";
          spec = "0.23.0+rocm6.4";
        }
        # AI-NOTE: Triton issues will be handled by global overlay
      ];
    additionalPipArgs = ["--extra-index-url" "https://download.pytorch.org/whl/rocm6.4/"];

    installInstructions = ./install-instructions-rocm.json;

    # createPackage = throw "ROCm is currently broken";
    inherit createPackage; # Want to work on ROCm? Swap the line above with this
  };
}
