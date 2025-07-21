{ pkgs, config, ... }: {
  imports = [ ../common.nix ];

  networking.hostName = "auth";
  networking.interfaces.eth1.ipv4.addresses = [{
    address = "192.168.1.3";
    prefixLength = 24;
  }];

  services.kerberos_server = {
    enable = true;
    settings = {
      realms."EXAMPLE.COM" = {
        acl = [{
          principal = "kadmin/admin@EXAMPLE.COM";
          access = "all";
        }];
      };

      logging.debug = true;
    };
  };

  services.openldap =
    let
      dbDomain = "example.com";
      dbSuffix = "dc=example,dc=com";
    in
    {
      enable = true;
      urlList = [ "ldap:///" ];
      settings = {
        attrs.olcLogLevel = [ "stats" ];
        children = {
          "cn=schema".includes = [
            "${pkgs.openldap}/etc/schema/core.ldif"
            "${pkgs.openldap}/etc/schema/cosine.ldif"
            "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
            "${pkgs.openldap}/etc/schema/nis.ldif"
          ];
          "olcDatabase={1}mdb" = {
            attrs = {
              objectClass = [
                "olcDatabaseConfig"
                "olcMdbConfig"
              ];
              olcDatabase = "{1}mdb";
              olcDbDirectory = "/var/lib/openldap/db";
              olcSuffix = dbSuffix;
              olcAccess = [
                "{1}to * by * read"
              ];
            };
          };
        };
      };

      declarativeContents.${dbSuffix} = ''
        dn: ${dbSuffix}
        objectClass: top
        objectClass: dcObject
        objectClass: organization
        o: ${dbDomain}

        dn: ou=users,${dbSuffix}
        objectClass: top
        objectClass: organizationalUnit

        dn: uid=user1,ou=users,${dbSuffix}
        objectClass: person
        objectClass: posixAccount
        cn: "User 1"
        sn: ""
        uid: user1
        homeDirectory: /data/user1
        uidNumber: 1234
        gidNumber: 1234

        dn: uid=user2,ou=users,${dbSuffix}
        objectClass: person
        objectClass: posixAccount
        cn: "User 2"
        sn: ""
        uid: user2
        homeDirectory: /data/user2
        uidNumber: 1235
        gidNumber: 1235
      '';
    };

  systemd.services.create-realm = {
    path = [ config.security.krb5.package ];
    script = ''
      mkdir -p /var/lib/krb5kdc
      kdb5_util create -s -r EXAMPLE.COM -P master_key
    '';
    serviceConfig.Type = "oneshot";
    before = [ "kadmind.service" "kdc.service" ];
    wantedBy = [ "kadmind.service" "kdc.service" ];
  };

  systemd.services.create-principals = {
    serviceConfig.Type = "oneshot";
    after = [ "kadmind.service" ];
    wants = [ "kadmind.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.security.krb5.package ];
    script = ''
      kadmin.local change_password -pw admin kadmin/admin
      kadmin.local add_principal -pw password1 user1
      kadmin.local add_principal -pw password2 user2
      kadmin.local add_principal -randkey host/controller.example.com
      kadmin.local add_principal -randkey host/worker.example.com
      kadmin.local add_principal -randkey host/login.example.com
      kadmin.local add_principal -randkey host/nfs.example.com
      kadmin.local add_principal -randkey nfs/nfs.example.com
    '';
  };
}
