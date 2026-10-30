# AI SLOP
This is an AI-slopped flake because I wanted to try it out on nixos.

The original project can be found here: https://github.com/rywby-dot/waypie

## Installation
Add this to your flake inputs:
```
    waypie = {
      url = "git+https://github.com/luh-05/waypie-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.waypie-src.follows = "waypie-src";
    };

    waypie-src = {
      url = "git+https://github.com/rywby-dot/waypie";
      flake = false;
    };
```
Then import `waypie.homeManagerModules.default` and set `programs.waypie.enable = true`.
