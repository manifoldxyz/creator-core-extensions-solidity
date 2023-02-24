function toEthSignedMessageHash(messageHex) {
  const messageBuffer = Buffer.from(messageHex.substring(2), "hex");
  const prefix = Buffer.from(`\x19Ethereum Signed Message:\n${messageBuffer.length}`);
  return web3.utils.sha3(Buffer.concat([prefix, messageBuffer]));
}

function fixSignature(signature) {
  // in geth its always 27/28, in ganache its 0/1. Change to 27/28 to prevent
  // signature malleability if version is 0/1
  // see https://github.com/ethereum/go-ethereum/blob/v1.8.23/internal/ethapi/api.go#L465
  let v = parseInt(signature.slice(130, 132), 16);
  if (v < 27) {
    v += 27;
  }
  const vHex = v.toString(16);
  return signature.slice(0, 130) + vHex;
}

async function signTransaction(sender, nonce, signer) {
  let packedData = web3.utils.encodePacked({ value: sender, type: "address" }, { value: nonce, type: "bytes32" });
  let message = toEthSignedMessageHash(packedData);
  let signature = fixSignature(await web3.eth.sign(packedData, signer));

  return {
    message,
    signature,
  };
}
async function signTransactionWithAmount(sender, nonce, signer, amount) {
  let packedData = web3.utils.encodePacked(
    { value: sender, type: "address" },
    { value: nonce, type: "bytes32" },
    { value: amount, type: "uint16" }
  );
  let message = toEthSignedMessageHash(packedData);
  let signature = fixSignature(await web3.eth.sign(packedData, signer));

  return {
    message,
    signature,
  };
}

module.exports = {
  toEthSignedMessageHash,
  fixSignature,
  signTransaction,
  signTransactionWithAmount,
};
