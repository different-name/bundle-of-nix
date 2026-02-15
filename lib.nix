lib:
let
  bundleLib.mkEnableModule =
    optionPath: moduleConfig:
    let
      enableOptionPath = optionPath ++ [ "enable" ];
    in
    {
      imports = lib.singleton (
        { config, ... }:
        {
          options = lib.setAttrByPath enableOptionPath (lib.mkEnableOption "${lib.last optionPath} config");
          config = lib.mkIf (lib.getAttrFromPath enableOptionPath config) moduleConfig;
        }
      );
    };
in
bundleLib
