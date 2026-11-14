// SPDX-License-Identifier: CC0-1.0
import { hashTypedData } from "viem";

/// Lets the standard x402 client pay from an agent account.
///
/// The client asks its signer to sign the payment (an EIP-712 message of the token).
/// An agent account is a contract: it approves a hash only when its session key has signed
/// that hash wrapped as an `AgentMessage` of the account. So the payer is the account,
/// and the signature is the session key's signature over the wrapper.
///
/// `sessionKey`: a viem account (the agent's key). `account`: the agent account address.
export function agentSigner(sessionKey, account) {
  return {
    address: account,
    signTypedData: (payment) =>
      sessionKey.signTypedData({
        domain: {
          name: "AgentAccount",
          version: "1",
          chainId: payment.domain.chainId, // the account lives on the chain it pays on
          verifyingContract: account,
        },
        types: { AgentMessage: [{ name: "hash", type: "bytes32" }] },
        primaryType: "AgentMessage",
        message: { hash: hashTypedData(payment) },
      }),
  };
}
