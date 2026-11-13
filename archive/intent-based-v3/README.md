# Version 3 par intentions signées (piste écartée)

> Version 3 du prototype : écritures par intentions signées, ERC-721 classique désactivé.
> Écartée le 12 novembre 2026 au profit du standard à la racine de ce dépôt, qui restreint
> un ERC-721 normal. Ce code est conservé pour mémoire et n'est plus maintenu.

Prototype simplifié du standard « Agent-Only Tokens » pour Base, en Solidity.
Brouillon non audité, jamais déployé sur un réseau : les tests tournent dans
une blockchain simulée en local.

## Trois petits contrats

| Fichier | Rôle |
| --- | --- |
| `src/AgentOnlyNFT.sol` | Le cœur du standard. Sans argent, sans administrateur. |
| `src/AttestedAgentRegistry.sol` | La preuve d'agent, version 1 : enrôlement signé par plusieurs attesteurs. |
| `src/AgentOnlyNFTWithVault.sol` | Extension optionnelle : un coffre USDC par agent, pour vendre et prêter. |

Le cœur ne connaît le registre que par une fonction, `keyOf(agentId)`. On peut
donc remplacer la preuve d'agent sans toucher au token.

## Les trois règles du cœur

1. Les écritures ERC-721 classiques (`approve`, `transferFrom`…) échouent toujours.
2. Tout changement exige l'intention signée du détenteur, et l'accord du destinataire.
3. Seul un agent reconnu par le registre peut signer ou recevoir.

## Six opérations

Mint, transfert (don ou vente), burn, verrou, déverrouillage, saisie.
Le staking est un verrou personnel. Le prêt sur gage est un verrou au profit
du prêteur, qui peut saisir le token après l'échéance.

## Anti-spam

- Caution remboursable à l'enrôlement d'un agent (registre).
- Frais de mint et quota de mints par agent et par période (cœur).
- Aucun NFT ne peut arriver chez un agent sans son accord.

## Lancer les tests

    npm install
    git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
    forge test

Dix-sept tests, dont deux en fuzzing.

## Limites connues

- La garantie « aucun humain » repose sur l'honnêteté des attesteurs. Leur
  preuve est publiée par son empreinte, pour contrôle après coup et révocation.
- Les attesteurs sont fixés au déploiement : pas de rotation.
- Un agent retiré ou révoqué garde ses tokens, qui deviennent immobiles pour toujours.
- Pas de location, pas de `tokenURI`, pas de place de marché.
- Aucun audit, aucun déploiement, aucune mesure de gas sur Base.
