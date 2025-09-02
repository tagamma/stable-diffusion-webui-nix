{
  pkgs,
  fetchFromGitHub,
  mkWebuiDistrib,
  stdenv,
  ...
}: let
  sourceDerivation = stdenv.mkDerivation {
    name = "ComfyUI";

    src = fetchFromGitHub {
      owner = "comfyanonymous";
      repo = "ComfyUI";
      rev = "v0.3.43";
      hash = "sha256-gUa/9YGy6qlI1hHAYxn1q+zmJ4hyhYTjILnGmDM3Y3Q=";
    };

    patches = [];

    installPhase = ''
      cp -r . "$out"
    '';
  };

  createPackage = import ./package.nix;
in {
  cuda = mkWebuiDistrib {
    source = sourceDerivation;
    python = pkgs.python312;

    additionalRequirements = [
      # Required for most video extensions, common enough to be included
      # here
      {
        name = "diffusers";
        op = ">=";
        spec = "0.32.0";
      }
      {
        name = "accelerate";
        op = ">=";
        spec = "1.2.1";
      }
      {
        name = "transformers";
        op = ">=";
        spec = "4.49.1";
      }
      {
        name = "jax";
        op = ">=";
        spec = "0.4.28";
      }
      {
        name = "sentencepiece";
        op = ">=";
        spec = "0.2.0";
      }
      {name = "huggingface_hub";}
      {name = "einops";}
      {name = "peft";}
      {name = "opencv-python";}
      {name = "imageio-ffmpeg";}
      {name = "bitsandbytes";}
      {name = "matplotlib";}
      {name = "mss";}
      {name = "color-matcher";}
      {name = "ftfy";}
      {name = "protobuf";}
      {name = "sageattention";}
      {name = "timm";}
    ];

    installInstructions = ./install-instructions-cuda.json;

    requirementsFileName = "requirements.txt";

    inherit createPackage;
  };

  # AI-NOTE: ROCm variant for AMD GPU support
  rocm = mkWebuiDistrib {
    source = sourceDerivation;
    python = pkgs.python311; # Match Forge's Python version

    additionalRequirements = [
      # Base requirements (same as CUDA)
      {
        name = "diffusers";
        op = ">=";
        spec = "0.32.0";
      }
      {
        name = "accelerate";
        op = ">=";
        spec = "1.2.1";
      }
      {
        name = "transformers";
        op = ">=";
        spec = "4.49.1";
      }
      {
        name = "jax";
        op = ">=";
        spec = "0.4.28";
      }
      {
        name = "sentencepiece";
        op = ">=";
        spec = "0.2.0";
      }
      {name = "huggingface_hub";}
      {name = "einops";}
      {name = "peft";}
      {name = "opencv-python";}
      {name = "imageio-ffmpeg";}
      {name = "bitsandbytes";}
      {name = "matplotlib";}
      {name = "mss";}
      {name = "color-matcher";}
      {name = "ftfy";}
      {name = "protobuf";}
      {name = "sageattention";}
      {name = "timm";}

      # ROCm-specific torch versions
      {
        name = "torch";
        spec = "2.9.0.dev20250827+rocm6.4";
      }
      {
        name = "torchvision";
        spec = "0.24.0.dev20250827+rocm6.4";
      }
    ];

    additionalPipArgs = ["--extra-index-url" "https://download.pytorch.org/whl/nightly/rocm6.4/"];

    # AI-TODO: Create install-instructions-rocm.json for ComfyUI
    installInstructions = ./install-instructions-cuda.json; # Temporary fallback

    requirementsFileName = "requirements.txt";

    inherit createPackage;
  };
}
