# 1. StatefulSet для Kafka-клиента с фиксированным FQDN
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-client
spec:
  serviceName: "kafka-client"
  replicas: 4
  selector:
    matchLabels:
      app: kafka-client
  template:
    metadata:
      labels:
        app: kafka-client
    spec:
      hostname: kafka-client
      subdomain: example-subdomain
      containers:
      - name: kafka-client
        image: confluentinc/cp-kafka:latest
        env:
        - name: KAFKA_OPTS
          value: "-Djava.security.krb5.conf=/etc/krb5.conf"
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        command:
        - "/bin/bash"
        - "-c"
        - |
          echo "$(POD_IP) $(POD_NAME).example-subdomain.default.svc.cluster.local" >> /etc/hosts
          echo "$(hostname -i) $(hostname).example-subdomain.default.svc.cluster.local" >> /etc/hosts
          exec kafka-console-consumer ...  # Ваша команда запуска Kafka-клиента
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

---
# 2. Headless Service для StatefulSet
apiVersion: v1
kind: Service
metadata:
  name: example-subdomain
spec:
  clusterIP: None
  selector:
    app: kafka-client
  ports:
  - port: 9092

---
# 3. ConfigMap для client.properties
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-client-properties
data:
  client.properties: |
    security.protocol=SASL_PLAINTEXT
    sasl.mechanism=GSSAPI
    sasl.kerberos.service.name=kafka
    sasl.jaas.config=com.sun.security.auth.module.Krb5LoginModule required \
      useKeyTab=true \
      storeKey=true \
      keyTab="/etc/kafka/kafka-client.keytab" \
      principal="kafka-client/$(hostname).example-subdomain.default.svc.cluster.local@EXAMPLE.COM";

---
# 4. ConfigMap для krb5.conf
apiVersion: v1
kind: ConfigMap
metadata:
  name: krb5-conf
data:
  krb5.conf: |
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
    .example-subdomain.default.svc.cluster.local = EXAMPLE.COM
    example-subdomain.default.svc.cluster.local = EXAMPLE.COM

---
# 5. Network Policy для доступа к внешнему Kafka кластеру
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-kafka
spec:
  podSelector:
    matchLabels:
      app: kafka-client
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 192.168.2.0/24
    ports:
    - protocol: TCP
      port: 9093

---
# 6. CoreDNS ConfigMap для настройки обратного DNS
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  example-subdomain.server: |
    example-subdomain.default.svc.cluster.local:53 {
        errors
        cache 30
        forward . 10.0.0.2
    }
  2.0.10.in-addr.arpa.server: |
    2.0.10.in-addr.arpa:53 {
        errors
        cache 30
        forward . 10.0.0.2
    }
