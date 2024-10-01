apiVersion: v1
   kind: ConfigMap
   metadata:
     name: coredns-custom
     namespace: kube-system
   data:
     kubernetes.server: |
       kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
       }
     forward.server: |
       forward . /etc/resolv.conf
     custom.server: |
       kerberos.local:53 {
         file /etc/coredns/kerberos.db
         log
       }
     kerberos.db: |
       $ORIGIN kerberos.local.
       @       3600 IN SOA sns.dns.icann.org. noc.dns.icann.org. (
                     2017042745 ; serial
                     7200       ; refresh (2 hours)
                     3600       ; retry (1 hour)
                     1209600    ; expire (2 weeks)
                     3600       ; minimum (1 hour)
                     )

       $ORIGIN kerberos.local.
       @       IN NS server
       server  IN A  10.0.0.1
       kafka1  IN A  10.0.0.10
       kafka2  IN A  10.0.0.11
       kafka3  IN A  10.0.0.12
