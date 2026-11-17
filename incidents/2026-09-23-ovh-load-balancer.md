# Load Balancer Octavia EU-WEST-PAR : coupures répétées (nouvelles connexions refusées), membres sains, le 23/09/2026

Bonjour,

Nous avons subi aujourd'hui, le 23/09/2026, 13 coupures de service de 1 à 2 minutes chacune sur notre Load Balancer Public Cloud. Pendant toutes ces coupures, nos serveurs derrière le LB étaient sains et joignables en direct. Tout indique que le problème se situe au niveau du Load Balancer (amphora) ou du réseau en amont. Nous vous demandons d'analyser le LB aux heures indiquées ci-dessous.

## 1. Infrastructure concernée

- Projet Public Cloud : `25baddb77a674c1ab13f0db42f6e43ae`
- Région : EU-WEST-PAR
- Load Balancer : `potti_loadbalancer_par`, ID `5e98ff59-0a6b-47f9-8f25-0bc12ce50bbe`
  - VIP : `10.101.0.65`, Floating IP : `57.130.47.159`
- Listeners :
  - HTTP :80 (`3f34e9cb-8bc6-4e6b-82fa-59c9e853f94a`) : redirection L7 vers HTTPS
  - HTTPS :443 (`f24f3588-5403-4e05-b3c0-74430b5bdca0`) : pool PROXYV2 `1de6c441-ad41-461c-b2be-ac9dfdb01f59`, TLS terminé sur les serveurs
  - TCP :49984 (`f051f692-37cd-4307-97a2-c597eeff0833`) : pool TCP `45584937-32ba-4e70-93d8-d440e4c1b473`, pour les capteurs IoT
- Membres, identiques dans les deux pools :
  - `10.101.1.1` (AZ eu-west-par-a)
  - `10.101.2.1` (AZ eu-west-par-b)

## 2. Coupures de ce matin, avec l'ancienne configuration

Toute la matinée, le health monitor du pool HTTPS était de type **TCP** (delay 10s, timeout 5s, 3 essais). Ce type de check ne retire un membre du pool que si la connexion TCP échoue.

Coupures détectées par notre monitoring externe Oh Dear sur `https://potti.co` (heure de Paris) :

| Début    | Fin      | Durée     |
|----------|----------|-----------|
| 08:53:47 | 08:54:38 | 51s       |
| 08:55:50 | 08:56:42 | 52s       |
| 08:58:49 | 08:59:46 | 57s       |
| 09:00:49 | 09:02:36 | ~1 min 50 |
| 09:05:49 | 09:07:38 | ~1 min 50 |
| 09:10:47 | 09:12:38 | ~1 min 50 |
| 09:14:48 | 09:16:38 | ~1 min 50 |
| 09:17:49 | 09:20:36 | ~2 min 50 |
| 09:25:47 | 09:28:38 | ~2 min 50 |

Ce que nous avons constaté côté serveurs :

- **Le trafic reçu par nginx s'effondre pendant chaque coupure.** Autour des coupures, un serveur reçoit 15 à 180 requêtes par minute. Pendant les coupures, il en reçoit 0 à 6 (0 à 08:53, 1 à 4 entre 08:58 et 08:59, 3 à 6 entre 09:00 et 09:01). Les rares requêtes qui arrivent semblent venir de connexions HTTP/2 déjà établies. **Les nouvelles connexions n'atteignent pas les serveurs.**
- **Aucune erreur côté serveurs** : pas de timeout ni d'erreur upstream dans nginx, pas de saturation PHP-FPM (aucun message `max_children`). Les serveurs répondaient normalement.
- Le serveur `10.101.2.1` a été redémarré manuellement par nos soins à 09:27, pendant la dernière coupure, dans le cadre du diagnostic. Cette coupure avait commencé à 09:25:47, avant le redémarrage.
- Plus tôt dans la journée, nous avions aussi observé des périodes de latence élevée, **en même temps sur tous les listeners du LB, y compris le listener TCP 49984**. Ce listener a son propre pool et son propre monitor. Une dégradation simultanée des deux pools désigne un point commun : le LB lui-même.

## 3. Ce que nous avons mis en place en début d'après-midi

Pour mieux diagnostiquer, nous avons déployé :

1. **Un health check applicatif sur le pool HTTPS.** Monitor de type HTTP, `GET /up`, code attendu 200, delay 5s, timeout 3s. Il interroge un port dédié en HTTP simple, **20186**, configuré via `monitor_port` sur les membres, joignable uniquement depuis le réseau privé `10.101.0.0/16`. L'endpoint `/up` vérifie que l'application, la base PostgreSQL et Redis répondent. Il répond en environ 90 ms.
2. **Un monitoring direct de chaque serveur, sans passer par le LB.** Enregistrements DNS dédiés, `app-eu-west-par-a-1.potti.co` et `app-eu-west-par-b-1.potti.co`, surveillés par Oh Dear sur `http://<serveur>:20186/up`. Le port n'est ouvert qu'aux adresses IP publiées par Oh Dear.

Cela nous permet de comparer, pour un même moment, l'état de chaque serveur vu directement et l'état du service vu à travers le LB.

## 4. Coupures de cet après-midi

| Début    | Fin      | Durée     |
|----------|----------|-----------|
| 16:00:49 | 16:01:46 | 57s       |
| 16:04:48 | 16:07:41 | ~2 min 50 |
| 16:08:48 | 16:10:39 | ~1 min 50 |
| 16:19:50 | 16:21:39 | ~1 min 50 |

**Pendant ces 4 coupures, les monitors directs des deux serveurs n'ont enregistré aucune coupure.** Ces monitors appellent `/up`, qui teste aussi la base et Redis : l'application, la base et Redis étaient donc disponibles. Seul le chemin passant par le Load Balancer était coupé.

## 5. Notre analyse

- Les membres sont sains et joignables sur le réseau privé et en direct.
- Les coupures se produisent aussi bien avec un monitor TCP (le matin) qu'avec un monitor HTTP (l'après-midi). Elles ne dépendent donc pas du type de health check.
- Les nouvelles connexions n'atteignent pas les serveurs pendant les coupures, alors que les connexions déjà établies continuent de passer.
- Les coupures se produisent en rafales, avec une durée typique de 1 à 3 minutes, alors que notre trafic reste modeste.

Cela ressemble à un dysfonctionnement de l'amphora ou du réseau en amont : bascule entre amphorae, rechargements haproxy, ou perte de paquets entre la Floating IP et la VIP.

## 6. Nos questions

1. Pouvez-vous consulter les logs et métriques de l'amphora du LB `5e98ff59-0a6b-47f9-8f25-0bc12ce50bbe` aux heures ci-dessus : redémarrages ou bascules d'amphora, rechargements haproxy, CPU, connexions rejetées ?
2. Quel est le statut des membres (`operating_status`) enregistré par Octavia pendant ces coupures ?
3. Y a-t-il eu des événements réseau sur la Floating IP `57.130.47.159` ou sur le port de la VIP à ces heures ?
4. Y a-t-il eu un incident ou une maintenance sur l'infrastructure Load Balancer d'EU-WEST-PAR à ces heures ?

Merci d'avance pour votre retour,

Jonathan Jean, Potti
