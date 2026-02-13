{
  description = "bundle-of-nix";

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
