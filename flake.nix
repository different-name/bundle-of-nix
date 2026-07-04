{
  description = "flake-parts module for grouping nix config into feature-focused, cross-platform bundles";

  outputs =
    _:
    let
      flakeModules = {
        bundle = import ./module;
        default = flakeModules.bundle;
      };
    in
    {
      inherit flakeModules;
    };
}
