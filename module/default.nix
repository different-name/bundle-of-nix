{
  lib,
  config,
  withSystem,
  ...
}:
let
  inherit (lib) types;

  cfg = config.bundle;

  deconstructedConfigData = lib.mapAttrsToList (
    hostAttr: host:
    let
      class = cfg.systemClasses.${host.class} or (throw "No '${host.class}' system class found");
      finalConfig = cfg.finalHostConfigs.${hostAttr};

      validHomeClasses = lib.filter (
        homeClass:
        (lib.hasAttr host.class homeClass.system.classes) && (finalConfig.${homeClass.namespace} != [ ])
      ) (lib.attrValues cfg.homeClasses);

      homeConfigs =
        let
          transposeItem =
            child: parent: value:
            lib.singleton { inherit child parent value; };

          transposeItems = parent: lib.mapAttrsToList (transposeItem parent);

          deconstruct = lib.mapAttrsToList transposeItems;

          reconstruct = lib.foldl (
            acc: item:
            acc
            // {
              ${item.parent} = (acc.${item.parent} or { }) // {
                ${item.child} = item.value;
              };
            }
          ) { };

          transpose =
            attrs:
            lib.pipe attrs [
              deconstruct
              lib.flatten
              reconstruct
            ];
        in
        transpose cfg.finalUserConfigs.${hostAttr};

      finalHomeModules = lib.concatMap (
        homeClass:
        let
          systemClassCfg = homeClass.system.classes.${host.class};
          systemModule = systemClassCfg.module;
          inherit (systemClassCfg) usersAttrPath;

          userConfigs = homeConfigs.${homeClass.namespace};
          mappedHomeModules = lib.concatLists (
            lib.mapAttrsToList (
              userAttr: homeModules:
              let
                extraHomeConfig = withSystem host.system homeClass.extraHomeConfig;
              in
              map (homeModule: lib.setAttrByPath (usersAttrPath ++ [ userAttr ]) homeModule) (
                homeModules ++ [ extraHomeConfig ]
              )
            ) userConfigs
          );

          extraConfig = withSystem host.system homeClass.system.extraConfig;
        in
        [
          systemModule
          extraConfig
        ]
        ++ mappedHomeModules
      ) validHomeClasses;

      modules = finalConfig.${class.namespace} ++ finalHomeModules;
    in
    {
      ${class.flakeAttribute}.${hostAttr} = {
        inherit (class) mkSystem;

        args = {
          specialArgs = withSystem host.system class.specialArgs;
          modules = [ (withSystem host.system class.extraConfig) ] ++ modules;
        };
      };
    }
  ) cfg.hosts;

  configurationData = lib.foldl lib.recursiveUpdate { } deconstructedConfigData;

  configurations = lib.mapAttrs (
    _: hosts: lib.mapAttrs (_: { mkSystem, args }: mkSystem args) hosts
  ) configurationData;
in
{
  imports = [
    ./classes.nix
    ./hosts.nix
    ./users.nix
  ];

  options.bundle = {
    shared = lib.mkOption {
      type = types.deferredModule; # would be nice if we could type this, but i'm not sure how to since bundleModule needs access to system
      default = { };
      # TODO documentation
    };
  };

  config.flake = configurations;
}
