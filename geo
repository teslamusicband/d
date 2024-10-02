# Конфигурация для Кластера 1 (10.0.0.0/24)

---
# 1. StatefulSet для Kafka-клиента в Кластере 1
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-client-cluster1
spec:
  serviceName: "kafka-client-cluster1"
  replicas: 2
  selector:
    matchLabels:
      app: kafka-client
      cluster: cluster1
  template:
    metadata:
      labels:
        app: kafka-client
        cluster: cluster1
      annotations:
        k8s.v1.cni.cncf.io/networks: '[
          {
            "name": "egress-network-cluster1",
            "interface": "eth1"
          }
        ]'
    spec:
      hostname: kafka-client
      subdomain: example-subdomain-cluster1
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
        - name: EGRESS_IP
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['k8s.v1.cni.cncf.io/networks-status']
        command:
        - "/bin/bash"
        - "-c"
        - |
          EGRESS_IP=$(echo $EGRESS_IP | jq -r '.[1].ips[0]')
          echo "$POD_IP $(hostname).example-subdomain-cluster1.default.svc.cluster.local" >> /etc/hosts
          echo "$EGRESS_IP $(hostname)-egress.example-subdomain-cluster1.default.svc.cluster.local" >> /etc/hosts
          exec kafka-console-producer ...  # Ваша команда запуска Kafka-продюсера
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

---
# Конфигурация для Кластера 2 (10.1.0.0/24)

---
# 2. StatefulSet для Kafka-клиента в Кластере 2
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-client-cluster2
spec:
  serviceName: "kafka-client-cluster2"
  replicas: 2
  selector:
    matchLabels:
      app: kafka-client
      cluster: cluster2
  template:
    metadata:
      labels:
        app: kafka-client
        cluster: cluster2
      annotations:
        k8s.v1.cni.cncf.io/networks: '[
          {
            "name": "egress-network-cluster2",
            "interface": "eth1"
          }
        ]'
    spec:
      hostname: kafka-client
      subdomain: example-subdomain-cluster2
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
        - name: EGRESS_IP
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['k8s.v1.cni.cncf.io/networks-status']
        command:
        - "/bin/bash"
        - "-c"
        - |
          EGRESS_IP=$(echo $EGRESS_IP | jq -r '.[1].ips[0]')
          echo "$POD_IP $(hostname).example-subdomain-cluster2.default.svc.cluster.local" >> /etc/hosts
          echo "$EGRESS_IP $(hostname)-egress.example-subdomain-cluster2.default.svc.cluster.local" >> /etc/hosts
          exec kafka-console-producer ...  # Ваша команда запуска Kafka-продюсера
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

---
# 3. Multus NetworkAttachmentDefinition для egress сети Кластера 1
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: egress-network-cluster1
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "eth1",
    "mode": "bridge",
    "ipam": {
      "type": "host-local",
      "subnet": "192.168.1.0/24",
      "rangeStart": "192.168.1.200",
      "rangeEnd": "192.168.1.250",
      "routes": [
        { "dst": "192.168.2.0/24" }
      ],
      "gateway": "192.168.1.1"
    }
  }'

---
# 4. Multus NetworkAttachmentDefinition для egress сети Кластера 2
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: egress-network-cluster2
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "eth1",
    "mode": "bridge",
    "ipam": {
      "type": "host-local",
      "subnet": "192.168.3.0/24",
      "rangeStart": "192.168.3.200",
      "rangeEnd": "192.168.3.250",
      "routes": [
        { "dst": "192.168.2.0/24" }
      ],
      "gateway": "192.168.3.1"
    }
  }'

---
# 5. ConfigMap для client.properties (общий для обоих кластеров)
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
      principal="kafka-client/$(hostname)-egress.example-subdomain-${CLUSTER}.default.svc.cluster.local@EXAMPLE.COM";
    
    # Настройки для отказоустойчивости
    max.in.flight.requests.per.connection=1
    retries=Integer.MAX_VALUE
    acks=all
    enable.idempotence=true

---
# 6. ConfigMap для krb5.conf (общий для обоих кластеров)
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
        kdc = 192.168.2.3  # Резервный KDC
        admin_server = 192.168.2.2
    }

    [domain_realm]
    .example-subdomain-cluster1.default.svc.cluster.local = EXAMPLE.COM
    example-subdomain-cluster1.default.svc.cluster.local = EXAMPLE.COM
    .example-subdomain-cluster2.default.svc.cluster.local = EXAMPLE.COM
    example-subdomain-cluster2.default.svc.cluster.local = EXAMPLE.COM

---
# 7. Network Policy для доступа к внешнему KDC и Kafka кластеру (для обоих кластеров)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-kdc-and-kafka
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
      port: 88
    - protocol: UDP
      port: 88
    - protocol: TCP
      port: 749
    - protocol: TCP
      port: 9093
