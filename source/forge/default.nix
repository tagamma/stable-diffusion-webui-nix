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
        # NOTE: Use specific nightly PyTorch with ROCm 6.4 for RX 9000 series support
        {
          name = "torch";
          spec = "2.9.0.dev20250827+rocm6.4"; # Latest available ROCm 6.4 nightly
        }
        {
          name = "torchvision";
          spec = "0.24.0.dev20250827+rocm6.4"; # Compatible torchvision version
        }
        # TODO: Re-enable triton once build issues are resolved
        # Triton provides GPU kernel optimizations but isn't required for basic functionality
      ];
    additionalPipArgs = ["--extra-index-url" "https://download.pytorch.org/whl/nightly/rocm6.4/"];

    installInstructions = ./install-instructions-rocm.json;

    # createPackage = throw "ROCm is currently broken";
    inherit createPackage; # Want to work on ROCm? Swap the line above with this
  };
}
