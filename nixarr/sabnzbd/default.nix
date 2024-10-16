{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixarr.sabnzbd;
  nixarr = config.nixarr;
in {
  options.nixarr.sabnzbd = {
    enable = mkEnableOption "Enable the SABnzbd service.";

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/sabnzbd";
      defaultText = literalExpression ''"''${nixarr.stateDir}/sabnzbd"'';
      example = "/nixarr/.state/sabnzbd";
      description = ''
        The location of the state directory for the SABnzbd service.

        **Warning:** Setting this to any path, where the subpath is not
        owned by root, will fail! For example:

        ```nix
          stateDir = /home/user/nixarr/.state/sabnzbd
        ```

        Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    guiPort = mkOption {
      type = types.port;
      default = 8080;
      example = 9999;
      description = ''
        The port that SABnzbd's GUI will listen on for incomming connections.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.SABnzbd.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for SABnzbd";
    };

    whitelistHostnames = mkOption {
      type = types.listOf types.str;
      default = [config.networking.hostName];
      defaultText = "[ config.networking.hostName ]";
      example = ''[ "mediaserv" "media.example.com" ]'';
      description = ''
        A list that specifies what URLs that are allowed to represent your
        SABnzbd instance. If you see an error message like this when
        trying to connect to SABnzbd from another device...

        ```
        Refused connection with hostname "your.hostname.com"
        ```

        ...then you should add your hostname(s) to this list.

        SABnzbd only allows connections matching these URLs in order to prevent
        DNS hijacking. See <https://sabnzbd.org/wiki/extra/hostname-check.html>
        for more info.
      '';
    };

    whitelistRanges = mkOption {
      type = types.listOf types.str;
      default = [];
      defaultText = "[ ]";
      example = ''[ "192.168.1.0/24" "10.0.0.0/23" ]'';
      description = ''
        A list of IP ranges that will be allowed to connect to SABnzbd's
        web GUI. This only needs to be set if SABnzbd needs to be accessed
        from another machine besides its host.
      '';
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route SABnzbd traffic through the VPN.
      '';
    };
  };

  imports = [./config.nix];

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 usenet root - -"
    ];

    services.sabnzbd = {
      enable = true;
      user = "usenet";
      group = "media";
      configFile = "${cfg.stateDir}/sabnzbd.ini";
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.guiPort];

    systemd.services.sabnzbd.serviceConfig = {
      Restart = "on-failure";
      StartLimitBurst = 5;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.sabnzbd.vpnconfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnnamespace = "wg";
    };

    # Port mappings
    vpnnamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.guiPort;
          to = cfg.guiPort;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.guiPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.guiPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.guiPort}";
        };
      };
    };
  };
}
