{ lib, config, ... }:
let
  inherit (lib) types;

  cfg = config.bundle;
in
{
  options.bundle.users = lib.mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          shared = lib.mkOption {
            type = types.deferredModule;
            default = { };
            description = "Bundle configuration for all hosts under this user";
            example = lib.literalExpression "{ imports = [ (inputs.import-tree ./users/diffy/shared) ]; }";
          };

          # TODO assert that hosts here must be defined in cfg.hosts
          hosts = lib.mkOption {
            type = types.attrsOf types.deferredModule;
            apply =
              value:
              lib.mapAttrs (hostAttr: _: {
                _module.args.bundleInfo = { inherit (cfg.hosts.${hostAttr}) system; };
                imports = [ value.${hostAttr} ];
              }) value;
            description = "Bundle configuration for this host, under this user";
            example = lib.literalExpression ''
              {
                sodium.imports = [ (inputs.import-tree ./users/diffy/hosts/sodium) ];
                potassium.imports = [ (inputs.import-tree ./users/diffy/hosts/sodium) ];
              }
            '';
          };
        };
      }
    );
    default = { };
    description = ''
      User configuration, all configuration is applied through users

      Each user defined here represents a person (real user). These differ from users in the system itself (user account)

      A real user's configuration can create multiple user accounts if needed

      If you are the only one using your configuration, you would have only one real user
    '';
  };
}
