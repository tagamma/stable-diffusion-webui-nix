# The python wheels that are downloaded will usually not run
# on Nix because of linker issues/missing dependencies
#
# For these packages we need to apply special steps - this is done
# in form of an overlay to the python packages
{
  pkgs,
  python,
  pythonPkgs,
  lib,
}: final: prev: let
  hipblaslt = pkgs.callPackage ./hipblaslt {
    inherit python;
    inherit pythonPkgs;
  };

  # Add dependencies to a package
  withExtraDependencies = pkg: extraDeps:
    pkg.overridePythonAttrs (prev: {
      dependencies = prev.dependencies ++ extraDeps;
    });

  # Add zlib to a package
  withZlib = pkg: withExtraDependencies pkg [pkgs.zlib];

  # Hook for removing all compiled bytecode
  pythonRemoveBytecodeHook = pythonPkgs.callPackage (
    {makePythonHook}:
      makePythonHook {
        name = "python-remove-bytecode-hook";
        propagatedBuildInputs = [];
      }
      ./python-remove-bytecode-hook.sh
  ) {};

  # Hook for copying libraries to lib output
  pythonPropagateLibHook = pythonPkgs.callPackage (
    {makePythonHook}:
      makePythonHook {
        name = "python-propagate-lib-hook";
        propagatedBuildInputs = [];
        substitutions = {
          pythonSitePackages = python.sitePackages;
        };
      }
      ./python-propagate-lib-hook.sh
  ) {};

  # Remove all bytecode from the package
  removePythonBytecode = pkg:
    pkg.overridePythonAttrs (prev: {
      nativeBuildInputs = prev.nativeBuildInputs ++ [pythonRemoveBytecodeHook];
    });

  # Make sure the package has a lib output
  propagateLib = pkg:
    pkg.overrideAttrs (prev: {
      outputs = (prev.outputs or []) ++ ["lib"];
      nativeBuildInputs = prev.nativeBuildInputs ++ [pythonPropagateLibHook];
    });
in
  with pkgs; rec {
    inherit hipblaslt;

    # Numpy needs zlib and also needs to define coreIncludeDir so that scipy
    # can consume it
    numpy = prev.numpy.overridePythonAttrs (prevPyAttrs: {
      dependencies = prevPyAttrs.dependencies ++ [zlib];
      passthru =
        (prevPyAttrs.passthru or {})
        // {
          # Needed for nixpkgs scipy to build
          coreIncludeDir = "${final.numpy}/${python.sitePackages}/numpy/core/include";
        };
    });

    # A bunch of packages require zlib
    llvmlite = withZlib prev.llvmlite;
    tokenizers = withZlib prev.tokenizers;
    pillow = withZlib prev.pillow;
    av = withZlib prev.av;
    triton = withZlib (
      prev.triton.overridePythonAttrs (prev: {
        # https://github.com/NixOS/nixpkgs/issues/96654
        dontStrip = 1;
      })
    );

    # Random other dependencies
    opencv-python = withExtraDependencies prev.opencv-python [
      libGL
      glib

      libxcb
      libice
      libsm
    ];

    # Cuda stuff
    torch = propagateLib (
      prev.torch.overridePythonAttrs (prev: {
        # Will be added by pkgs.autoAddDriverRunpath
        # librocblas.so.4 is bundled as librocblas.so (unversioned) in the wheel
        autoPatchelfIgnoreMissingDeps = ["libcuda.so.1" "librocblas.so.4"];
        nativeBuildInputs = (prev.nativeBuildInputs or []) ++ [pkgs.autoAddDriverRunpath];

        # buildInputs is needed for autopatchelf to find native libraries
        buildInputs = (prev.buildInputs or []) ++ [
          pkgs.zlib
          pkgs.zstd
          pkgs.xz
          pkgs.bzip2
          pkgs.rocmPackages.rocblas
          pkgs.rocmPackages.rocsolver
          pkgs.rocmPackages.rocm-runtime
          pkgs.rocmPackages.rocsparse
          pkgs.rocmPackages.rocfft
        ];

        # Additional dependencies for ROCm 7.2 wheels (runtime propagation)
        dependencies =
          (prev.dependencies or [])
          ++ [
            # Compression libraries required by ROCm wheels
            pkgs.zlib # libz.so.1
            pkgs.zstd # libzstd.so.1
            pkgs.xz # liblzma.so.5
            pkgs.bzip2 # libbz2.so.1

            # ROCm libraries for AMD GPU support
            pkgs.rocmPackages.rocblas
            pkgs.rocmPackages.rocsolver
            pkgs.rocmPackages.rocm-runtime
            pkgs.rocmPackages.rocsparse
            pkgs.rocmPackages.rocfft
            # NOTE: hipblaslt excluded - only supports enterprise GPUs, not consumer RX series
          ];
      })
    );

    torchvision = propagateLib (
      prev.torchvision.overridePythonAttrs (prevAttrs: {
        autoPatchelfIgnoreMissingDeps = [
          "libamdhip64.so.6"
          "libamdhip64.so.7"
        ];

        nativeBuildInputs = (prevAttrs.nativeBuildInputs or []) ++ [pkgs.autoAddDriverRunpath];

        buildInputs = (prevAttrs.buildInputs or []) ++ [
          pkgs.zlib
          pkgs.zstd
          pkgs.rocmPackages.rocblas
          pkgs.rocmPackages.rocsolver
          pkgs.rocmPackages.rocm-runtime
          pkgs.rocmPackages.rocsparse
          pkgs.rocmPackages.rocfft
          pkgs.rocmPackages.miopen
          pkgs.rocmPackages.hipblas
        ];

        # torchvision's _meta_registrations.py tries to register fake ops for operators
        # like torchvision::nms, but on ROCm the C++ extension doesn't load them the same
        # way. We wrap the entire module in a try/except so the import doesn't crash.
        postInstall = (prevAttrs.postInstall or "") + ''
          meta_reg="$out/${python.sitePackages}/torchvision/_meta_registrations.py"
          if [ -f "$meta_reg" ]; then
            echo "Patching torchvision _meta_registrations.py for ROCm compatibility..."
            ${pkgs.python312}/bin/python3 -c "
import textwrap, sys
path = sys.argv[1]
with open(path) as f:
    original = f.read()
# Wrap everything after the imports in a try/except
# Find the first @torch.library line and wrap from there
lines = original.split('\n')
wrap_start = None
for i, line in enumerate(lines):
    if '@torch.library.register_fake' in line:
        wrap_start = i
        break
if wrap_start is not None:
    header = '\n'.join(lines[:wrap_start])
    body = '\n'.join(lines[wrap_start:])
    indented = textwrap.indent(body, '    ')
    patched = header + '\ntry:\n' + indented + '\nexcept (RuntimeError, AttributeError):\n    pass  # C++ ops not registered on ROCm, fake registrations not needed\n'
    with open(path, 'w') as f:
        f.write(patched)
    print('Patched successfully')
else:
    print('No register_fake found, skipping patch')
" "$meta_reg"
          fi
        '';
      })
    );

    torchaudio = propagateLib (
      prev.torchaudio.overridePythonAttrs (prev: {
        dependencies = [
          pkgs.ffmpeg_6
          pkgs.sox
          torch
        ];

        # We provide ffmpeg 6 and don't need ROCm HIP for audio (falls back to CPU)
        autoPatchelfIgnoreMissingDeps = [
          # ffmpeg 5
          "libavutil.so.57"
          "libavcodec.so.59"
          "libavformat.so.59"
          "libavfilter.so.8"
          "libavutil.so.57"
          "libavdevice.so.59"

          # ffmpeg 4
          "libavutil.so.56"
          "libavcodec.so.58"
          "libavformat.so.58"
          "libavfilter.so.7"
          "libavutil.so.56"
          "libavdevice.so.58"

          # ROCm 7.x HIP libraries (torchaudio falls back to CPU if missing)
          "libMIOpen.so.1"
          "libhipblas.so.3"
          "libhipfft.so.0"
          "libhipsparse.so.4"
          "libhipsolver.so.1"
        ];
      })
    );

    bitsandbytes = (
      prev.bitsandbytes.overridePythonAttrs (prev: {
        # bitsandbytes ships with multiple backend libraries for different hardware
        # (CUDA 11/12/13, ROCm 6.x/7.x, Intel XPU). It selects automatically at runtime.
        autoPatchelfIgnoreMissingDeps = [
          # CUDA 11.x
          "libcudart.so.11.0"
          "libcublas.so.11"
          "libcusparse.so.11"
          "libcublasLt.so.11"

          # CUDA 12.x
          "libcudart.so.12"
          "libcublas.so.12"
          "libcusparse.so.12"
          "libcublasLt.so.12"
          "libnvJitLink.so.12"

          # CUDA 13.x
          "libcudart.so.13"
          "libcublas.so.13"
          "libcusparse.so.13"
          "libcublasLt.so.13"
          "libnvJitLink.so.13"

          # ROCm 6.x
          "libhipblas.so.2"
          "libhipsparse.so.1"
          "libhipblaslt.so.0"

          # ROCm 7.x
          "libhipblas.so.3"
          "libhipsparse.so.4"

          # Intel XPU
          "libirng.so"
          "libimf.so"
          "libintlc.so.5"
          "libsycl.so.8"
          "libsvml.so"
        ];
      })
    );
    
    # comfy-aimdo ships a native .so that expects libcuda.so.1 (provided by the driver at runtime)
    comfy-aimdo = prev.comfy-aimdo.overridePythonAttrs (prevAttrs: {
      autoPatchelfIgnoreMissingDeps = ["libcuda.so.1"];
      nativeBuildInputs = (prevAttrs.nativeBuildInputs or []) ++ [pkgs.autoAddDriverRunpath];
    });

    numba = withExtraDependencies prev.numba (let
      tbb = 
        if pkgs ? tbb_2022
          then pkgs.tbb_2022
        else if pkgs ? tbb_2021
          then pkgs.tbb_2021
        else pkgs.tbb_2021_11;
    in [
      tbb
    ]);
    
    filterpy = prev.filterpy.overridePythonAttrs (prev: {
      # Fails for some reason
      doCheck = false;
    });

    jsonmerge = prev.jsonmerge.overridePythonAttrs (prev: {
      # No idea either, 2 tests fail
      doCheck = false;
    });

    # Bytecode removal (thanks NVIDIA for shipping libraries with overlapping bytecode..)
    nvidia-nvjitlink-cu12 = propagateLib (removePythonBytecode prev.nvidia-nvjitlink-cu12);
    nvidia-cusparse-cu12 = propagateLib (removePythonBytecode prev.nvidia-cusparse-cu12);
    nvidia-cusparselt-cu12 = propagateLib (removePythonBytecode prev.nvidia-cusparselt-cu12);
    nvidia-cusolver-cu12 = propagateLib (removePythonBytecode prev.nvidia-cusolver-cu12);
    nvidia-cudnn-cu12 = propagateLib (removePythonBytecode (withZlib prev.nvidia-cudnn-cu12));
    nvidia-cuda-cupti-cu12 = propagateLib (removePythonBytecode prev.nvidia-cuda-cupti-cu12);
    nvidia-cublas-cu12 = propagateLib (removePythonBytecode prev.nvidia-cublas-cu12);
    nvidia-cuda-nvrtc-cu12 = propagateLib (removePythonBytecode prev.nvidia-cuda-nvrtc-cu12);
    nvidia-cuda-runtime-cu12 = propagateLib (removePythonBytecode prev.nvidia-cuda-runtime-cu12);
    nvidia-curand-cu12 = propagateLib (removePythonBytecode prev.nvidia-curand-cu12);
    nvidia-cufft-cu12 = propagateLib (removePythonBytecode prev.nvidia-cufft-cu12);
    nvidia-nccl-cu12 = propagateLib (removePythonBytecode prev.nvidia-nccl-cu12);
    nvidia-nvtx-cu12 = propagateLib (removePythonBytecode prev.nvidia-nvtx-cu12);
    nvidia-cufile-cu12 = propagateLib (
      withExtraDependencies (removePythonBytecode prev.nvidia-cufile-cu12) [
        pkgs.rdma-core
      ]
    );

    # ROCm specific stuff - triton-rocm (renamed from pytorch-triton-rocm in torch 2.11+)
    triton-rocm = withExtraDependencies prev.triton-rocm [
      pkgs.zlib # libz.so.1
      pkgs.zstd # libzstd.so.1
      pkgs.xz # liblzma.so.5
      pkgs.bzip2 # libbz2.so.1
    ];

    # Extra packages
    webui-python-raw = python;
    webui-python-env = python.withPackages (_: final.allRequirements);
  }
