# agent-only-core (mis de côté)

> Ce crate modélise la version 2 du projet (dix opérations). Le prototype a été
> simplifié depuis : la référence est maintenant le code à la racine de ce dépôt.
> Ce code est conservé pour mémoire et n'est plus maintenu.

Spécification exécutable, en Rust pur, du profil « Agent-Only Tokens ».

Elle modélise ce que le contrat devra imposer :

- chaque écriture passe par des intentions EIP-712 signées par la clé de session d'un agent enrôlé ;
- dix opérations : mint, transfert, vente, staking, sortie, location, gage, remboursement, saisie, burn ;
- un token n'a qu'un état à la fois : libre, en staking, loué ou gagé ;
- les paiements se règlent dans un coffre, dans la même opération.

## Lancer les tests

    cargo test

Onze tests : le cycle de vie complet, neuf attaques qui doivent échouer
(wallet humain, NFT non sollicité, rejeu, rejeu d'un mint, relais qui modifie les termes,
ancienne clé de session, sponsor, paiement impossible, saisie abusive),
et 20 000 opérations aléatoires avec vérification des invariants après chacune.

## Ce que ce crate ne couvre pas

- Aucune attestation matérielle n'est vérifiée : `enroll` reçoit un booléen.
- Ce n'est pas un contrat déployable. C'est la logique de référence, à porter
  en Solidity (Base) ou en Rust avec Stylus (Arbitrum).
- Pas de seconde attestation au-dessus d'un plafond, pas de frais de mint.
- Code non audité.

## Défaut de conception corrigé

Dans la première version, un token gagé restait bloqué si le prêteur était gelé
ou n'était plus enrôlé après l'échéance. Le remboursement reste désormais
possible après l'échéance tant que le prêteur n'a pas saisi le token.

## Vecteur de test croisé

    cargo run --example vector -- <adresse du contrat>

affiche l'empreinte EIP-712 d'une intention fixe. Le test Solidity
`test_VectorMatchesRust` vérifie que le contrat calcule la même.
