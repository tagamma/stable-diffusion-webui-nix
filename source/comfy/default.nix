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
      rev = "v0.18.3";
      hash = "sha256-ivyNuXXJJtmaXPgEJAwCESa+QgGzXawwQUw6m9A3X0o=";
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
        spec = "4.50.3";
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
    python = pkgs.python312;

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
        spec = "4.50.3";
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

    requirementsFileName = "requirements.txt";

    inherit createPackage;
  };
}
