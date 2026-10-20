{ lib, getSystem }:
let
  bundleLib = {
    mkEnableModule =
      optionPath: moduleConfig:
      let
        enableOptionPath = optionPath ++ [ "enable" ];
      in
      {
        imports = (moduleConfig.imports or [ ]) ++ [
          { options = lib.setAttrByPath optionPath (moduleConfig.options or { }); }
          (
            { config, ... }:
            {
              options = lib.setAttrByPath enableOptionPath (lib.mkEnableOption "${lib.last optionPath} config");
              config = lib.mkIf (lib.getAttrFromPath enableOptionPath config) (
                removeAttrs moduleConfig [
                  "imports"
                  "options"
                ]
              );
            }
          )
        ];
      };

    transpose =
      let
        deconstruct = lib.mapAttrsToList (
          parentAttr: children:
          lib.mapAttrsToList (childAttr: value: {
            ${childAttr}.${parentAttr} = value;
          }) children
        );

        reconstruct = builtins.zipAttrsWith (_: lib.mergeAttrsList);
      in
      attrs:
      lib.pipe attrs [
        deconstruct
        lib.flatten
        reconstruct
      ];

    withSystemExtraArgs =
      system: args: f:
      f ((getSystem system).allModuleArgs // args);
  };
in
bundleLib
