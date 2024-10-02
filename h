# 1. KDC Configuration (on 192.168.2.2)
# File: /etc/krb5.conf
[libdefaults]
    default_realm = EXAMPLE.COM
    dns_lookup_realm = false
    dns_lookup_kdc = false

[realms]
    EXAMPLE.COM = {
        kdc = 192.168.2.2
        admin_server = 192.168.2.2
    }

[domain_realm]
    .example.com = EXAMPLE.COM
    example.com = EXAMPLE.COM

# 2. Kubernetes DNS configuration
# File: coredns-custom.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  example.com.server: |
    example.com:53 {
        errors
        cache 30
        forward . 192.168.2.2
    }

# 3. Kafka broker JAAS configuration
# File: kafka_server_jaas.conf
KafkaServer {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab="/etc/kafka/kafka.keytab"
    principal="kafka/kafka.example.com@EXAMPLE.COM";
};

# 4. Kafka broker configuration
# File: server.properties
listeners=SASL_PLAINTEXT://0.0.0.0:9093
security.inter.broker.protocol=SASL_PLAINTEXT
sasl.mechanism.inter.broker.protocol=GSSAPI
sasl.enabled.mechanisms=GSSAPI
sasl.kerberos.service.name=kafka

# 5. Kafka client configuration
# File: client.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=GSSAPI
sasl.kerberos.service.name=kafka
sasl.jaas.config=com.sun.security.auth.module.Krb5LoginModule required \
    useKeyTab=true \
    storeKey=true \
    keyTab="/etc/kafka/kafka-client.keytab" \
    principal="kafka-client@EXAMPLE.COM";

# 6. Kubernetes Pod template for Kafka client
apiVersion: v1
kind: Pod
metadata:
  name: kafka-client
spec:
  containers:
  - name: kafka-client
    image: confluentinc/cp-kafka:latest
    volumeMounts:
    - name: krb5-conf
      mountPath: /etc/krb5.conf
      subPath: krb5.conf
    - name: kafka-client-keytab
      mountPath: /etc/kafka/kafka-client.keytab
      subPath: kafka-client.keytab
    - name: client-properties
      mountPath: /etc/kafka/client.properties
      subPath: client.properties
  volumes:
  - name: krb5-conf
    configMap:
      name: krb5-conf
  - name: kafka-client-keytab
    secret:
      secretName: kafka-client-keytab
  - name: client-properties
    configMap:
      name: kafka-client-properties

# 7. Kubernetes network policy to allow egress to KDC
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kdc-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 192.168.2.2/32
    ports:
    - protocol: TCP
      port: 88
    - protocol: UDP
      port: 88
