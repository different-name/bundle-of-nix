{
  lib,
  config,
  getSystem,
  ...
}:
let
  bundleLib = import ../lib.nix { inherit lib getSystem; };

  inherit (lib) types;
  inherit (bundleLib) transpose withSystemExtraArgs;

  cfg = config.bundle;
in
{
  imports = map (module: import module bundleLib) [
    ./platforms.nix
    ./hosts.nix
    ./users.nix
  ];

  options.bundle = {
    specialArgs = lib.mkOption {
      type = types.attrs;
      default = { };
      example = lib.literalExpression "{ inherit veryYippieLib; }";
      description = "`specialArgs` passed to bundle. This option can be used to pass additional arguments to all bundle modules";
    };

    shared = lib.mkOption {
      type = types.deferredModule;
      default = { };
      description = "Bundle configuration shared between all users and their hosts";
    };
  };

  config.flake =
    let
      throwOnErrors =
        errors: value:
        if errors != [ ] then throw "bundle:\n  ${lib.concatStringsSep "\n  " errors}" else value;

      # a host missing from bundle.hosts would silently drop the user's config for it
      unknownHostErrors = lib.concatLists (
        lib.mapAttrsToList (
          userAttr: user:
          map (
            hostAttr:
            "bundle.users.${userAttr}.hosts.${hostAttr}: host \"${hostAttr}\" is not declared in bundle.hosts"
          ) (lib.filter (hostAttr: !(cfg.hosts ? ${hostAttr})) (lib.attrNames user.hosts))
        ) cfg.users
      );

      systemHosts = lib.filterAttrs (_: host: host.systemPlatform != null) cfg.hosts;
      systemlessHosts = lib.filterAttrs (_: host: host.systemPlatform == null) cfg.hosts;

      hostConfigurations = lib.mapAttrs (
        hostAttr: host:
        let
          # complete bundled configuration for this host
          sysBundle = cfg.bundlesByHost.${hostAttr};
          # complete bundled configurations for each user of this host
          homeBundles = cfg.bundlesByHostUser.${hostAttr};

          sysPlatformAttr = host.systemPlatform;
          sysPlatform =
            cfg.systemPlatforms.${sysPlatformAttr} or (throw "No '${sysPlatformAttr}' system-platform found");

          specialArgs = withSystemExtraArgs host.system { host = hostAttr; } sysPlatform.specialArgs;
          sysModules =
            let
              extraConfig = withSystemExtraArgs host.system { host = hostAttr; } sysPlatform.extraConfig;
            in
            [ extraConfig ] ++ sysBundle.${sysPlatform.namespace};

          isUsed = homePlatform: sysBundle.${homePlatform.namespace} != [ ];
          hasSystemModule = homePlatform: lib.hasAttr sysPlatformAttr homePlatform.attachTo;

          # home-platforms that are in use, and have a usable module
          usedHomePlatforms = lib.filter (homePlatform: isUsed homePlatform && hasSystemModule homePlatform) (
            lib.attrValues cfg.homePlatforms
          );

          # a used home-platform with no module here would otherwise be dropped silently
          unattachedErrors = lib.concatMap (
            homePlatform:
            lib.optional (isUsed homePlatform && !hasSystemModule homePlatform)
              "bundle host \"${hostAttr}\": home-platform \"${homePlatform.namespace}\" has configuration but no module for system-platform \"${sysPlatformAttr}\""
          ) (lib.attrValues cfg.homePlatforms);

          # configuration modules to import for home-platform -> user
          # transposed from cfg.bundlesByHostUser.<host>
          modulesByHomePlatformUser = transpose homeBundles;

          # system modules from each home-platform that is in use
          # this includes the system module & extraConfig for the home-platform itself e.g.
          #   inputs.home-manager.nixosModules.default
          # as well as home level imports & extraHomeConfig mapped to system config e.g.
          #   { home-manager.users.diffy.imports = [ { home.username = "diffy"; } ]; }
          sysModulesFromHomePlatforms = lib.concatMap (
            homePlatform:
            let
              attachment = homePlatform.attachTo.${sysPlatformAttr};

              extraConfig = withSystemExtraArgs host.system {
                host = hostAttr;
              } attachment.extraConfig;

              inherit (attachment) module usersAttrPath;
              homeModulesByUser = modulesByHomePlatformUser.${homePlatform.namespace};

              mappedHomeModules = lib.mapAttrsToList (
                userAttr: homeModules:
                let
                  extraHomeConfig = withSystemExtraArgs host.system {
                    host = hostAttr;
                    user = userAttr;
                  } homePlatform.extraHomeConfig;
                in
                lib.setAttrByPath usersAttrPath {
                  ${userAttr}.imports = [ extraHomeConfig ] ++ homeModules;
                }
              ) homeModulesByUser;
            in
            [
              module
              extraConfig
            ]
            ++ mappedHomeModules
          ) usedHomePlatforms;
        in
        {
          inherit sysPlatform;
          errors = unattachedErrors;

          args = {
            inherit specialArgs;
            modules = sysModules ++ sysModulesFromHomePlatforms;
          };
        }
      ) systemHosts;

      systemConfigurations = transpose (
        lib.mapAttrs (
          _: hostConfiguration:
          let
            inherit (hostConfiguration) sysPlatform args errors;
          in
          {
            ${sysPlatform.flakeAttribute} = throwOnErrors errors (sysPlatform.mkSystem args);
          }
        ) hostConfigurations
      );

      standaloneErrors = lib.concatLists (
        lib.mapAttrsToList (
          hostAttr: _:
          let
            modulesByHomePlatformUser = transpose cfg.bundlesByHostUser.${hostAttr};
          in
          lib.concatMap (
            homePlatform:
            let
              usedUsers = lib.filterAttrs (_: mods: mods != [ ]) (
                modulesByHomePlatformUser.${homePlatform.namespace} or { }
              );
            in
            lib.optional (homePlatform.standalone == null && usedUsers != { })
              "bundle host \"${hostAttr}\": home-platform \"${homePlatform.namespace}\" has configuration but no standalone builder"
          ) (lib.attrValues cfg.homePlatforms)
        ) systemlessHosts
      );

      standaloneHomeConfigurations = lib.foldl' lib.recursiveUpdate { } (
        lib.mapAttrsToList (
          hostAttr: host:
          let
            modulesByHomePlatformUser = transpose cfg.bundlesByHostUser.${hostAttr};
            pkgs = (getSystem host.system).allModuleArgs.pkgs;

            standaloneHomePlatforms = lib.filter (homePlatform: homePlatform.standalone != null) (
              lib.attrValues cfg.homePlatforms
            );
          in
          lib.foldl' lib.recursiveUpdate { } (
            lib.concatMap (
              homePlatform:
              let
                inherit (homePlatform) standalone;
                usedUsers = lib.filterAttrs (_: mods: mods != [ ]) (
                  modulesByHomePlatformUser.${homePlatform.namespace} or { }
                );
              in
              lib.mapAttrsToList (
                userAttr: homeModules:
                let
                  extraArgs = {
                    host = hostAttr;
                    user = userAttr;
                  };

                  specialArgs = withSystemExtraArgs host.system extraArgs standalone.specialArgs;
                  extraHomeConfig = withSystemExtraArgs host.system extraArgs homePlatform.extraHomeConfig;
                in
                {
                  ${standalone.flakeAttribute}."${userAttr}@${hostAttr}" = standalone.mkSystem {
                    inherit pkgs specialArgs;
                    modules = [ extraHomeConfig ] ++ homeModules;
                  };
                }
              ) usedUsers
            ) standaloneHomePlatforms
          )
        ) systemlessHosts
      );

      errors = unknownHostErrors ++ standaloneErrors;
    in
    throwOnErrors errors (lib.recursiveUpdate systemConfigurations standaloneHomeConfigurations);
}
