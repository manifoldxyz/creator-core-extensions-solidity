const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ManifoldERC721LazyMint = artifacts.require('ManifoldERC721LazyMint');

contract('Manifold Lazy Mint', function ([...accounts]) {
  const [
    owner,
    another1,
    another2,
    another3,
    anyone,
    someone,
    ] = accounts;

  describe('Manifold Lazy Mint', function() {
    let creator1;
    let creator2;
    let creator3;
    let lazymint;

    beforeEach(async function () {
      creator1 = await ERC721Creator.new('c1', 'c1', {from:another1});
      creator2 = await ERC721Creator.new('c2', 'c2', {from:another2});
      creator3 = await ERC721Creator.new('c3', 'c3', {from:another3});

      lazymint = await ManifoldERC721LazyMint.new({from:owner});

      await creator1.registerExtension(lazymint.address, "", {from:another1});
      await creator2.registerExtension(lazymint.address, "", {from:another2});
      await creator3.registerExtension(lazymint.address, "", {from:another3});
    });

    it('access test', async function () {
      await truffleAssert.reverts(lazymint.createDrop(creator1.address, "", 1, 1, 1, 1, {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(lazymint.activatePremintPhase(creator1.address, 1, {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(lazymint.activateSalePhase(creator1.address, 1, {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(lazymint.deactivateSales(creator1.address, 1, {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(lazymint.reveal(creator1.address, 1, "./baseURI", {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(lazymint.withdraw(creator1.address, 1, anyone, {from:owner}), "Must be owner or admin of creator contract");
    });

    it('create drop', async function () {
      await lazymint.createDrop(creator1.address, "./placeholderURI", 100, 10, 1, 5, {from:another1});
      assert.equal(100, await lazymint.maxSupply(creator1.address, 1));
      assert.equal(10, await lazymint.mintPrice(creator1.address, 1));
      assert.equal(1, await lazymint.premintPrice(creator1.address, 1));
      assert.equal(5, await lazymint.maxTokensPerAddress(creator1.address, 1));
      assert.equal(0, await lazymint.salePhase(creator1.address, 1));
    });


    it('set and update allow list', async function () {
      await lazymint.createDrop(creator1.address, "./placeholderURI", 100, 10, 1, 5, {from:another1});
      assert.equal(false, await lazymint.isInAllowList(creator1.address, 1, another2));
      assert.equal(false, await lazymint.isInAllowList(creator1.address, 1, another3));

      await lazymint.setAllowList(creator1.address, 1, [another2, another3], {from:another1});
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another2));
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another3));

      await lazymint.setAllowList(creator1.address, 1, [another2], {from:another1});
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another2));
      assert.equal(false, await lazymint.isInAllowList(creator1.address, 1, another3));
    });

    it('activate and deactivate sale for drop', async function () {
      await lazymint.createDrop(creator1.address, "./placeholderURI", 100, 10, 1, 5, {from:another1});
      assert.equal(0, await lazymint.salePhase(creator1.address, 1));

      await lazymint.activatePremintPhase(creator1.address, 1, {from:another1});
      assert.equal(1, await lazymint.salePhase(creator1.address, 1));

      await lazymint.activateSalePhase(creator1.address, 1, {from:another1});
      assert.equal(2, await lazymint.salePhase(creator1.address, 1));

      await lazymint.deactivateSales(creator1.address, 1, {from:another1});
      assert.equal(0, await lazymint.salePhase(creator1.address, 1));
    });

    it('premint a token', async function () {
      // 1. Create drop and configure
      await lazymint.createDrop(creator1.address, "./placeholderURI", 4, 10, 1, 3, {from:another1});

      // 2. Set allow list
      await lazymint.setAllowList(creator1.address, 1, [another2, another3], {from:another1});
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another2));
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another3));

      // 3. Activate premint
      // Can't premint if sale is not activated
      await truffleAssert.reverts(lazymint.premint(creator1.address, 1, 1, {from:another2}), "Pre-mint is not active");
      // Activate premint
      await lazymint.activatePremintPhase(creator1.address, 1, {from:another1});
      assert.equal(1, await lazymint.salePhase(creator1.address, 1));

      // 4. Premint
      // Accounts not in the allow list can't premint
      await truffleAssert.reverts(lazymint.premint(creator1.address, 1, 1, {from:owner}), "Account is not in the allow list");
      // Not enough eth
      await truffleAssert.reverts(lazymint.premint(creator1.address, 1, 1, {from:another2}), "Ether value sent is not correct");
      await truffleAssert.reverts(lazymint.premint(creator1.address, 1, 3, {value: 1, from:another2}), "Ether value sent is not correct");
      // Preminted!
      await lazymint.premint(creator1.address, 1, 1, {value: 1, from:another2});
      await lazymint.premint(creator1.address, 1, 2, {value: 2, from:another2});
      // Too many tokens
      await truffleAssert.reverts(lazymint.premint(creator1.address, 1, 1, {value: 1, from:another2}), "Exceeded max available to purchase");
      // Sold out
      await truffleAssert.reverts(lazymint.premint(creator1.address, 1, 3, {value: 3, from:another3}), "Purchase would exceed max tokens");
      // Placeholder URI
      assert.equal("./placeholderURI" , await lazymint.tokenURI(creator1.address, 1, {from:another2}));

      // 5. Reveal
      await lazymint.reveal(creator1.address, 1, "./baseURI/", {from:another1});
      assert.equal("./baseURI/1" , await lazymint.tokenURI(creator1.address, 1, {from:another2}));
      assert.equal("./baseURI/2" , await lazymint.tokenURI(creator1.address, 2, {from:another2}));

      // 6. Withdraw
      assert.equal(3, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(3, await lazymint.totalToWithdraw(creator1.address, 1));

      const balance = await web3.eth.getBalance(anyone);
      await lazymint.withdraw(creator1.address, 1, anyone, {from:another1});
      const expectedBalance = web3.utils.toBN(balance).iadd(web3.utils.toBN(3));
      const updatedBalance = web3.utils.toBN((await web3.eth.getBalance(anyone)));
      assert.deepEqual(expectedBalance, updatedBalance);
    });

    it('mint a token', async function () {
      // 1. Create drop and configure
      await lazymint.createDrop(creator1.address, "./placeholderURI", 4, 10, 1, 3, {from:another1});

      // 2. Activate mint
      // Can't mint if sale is not activated
      await truffleAssert.reverts(lazymint.mint(creator1.address, 1, 1, {from:another2}), "Sale is not active");
      // Activate mint
      await lazymint.activateSalePhase(creator1.address, 1, {from:another1});
      assert.equal(2, await lazymint.salePhase(creator1.address, 1));

      // 4. Mint
      // Not enough eth
      await truffleAssert.reverts(lazymint.mint(creator1.address, 1, 1, {from:another2}), "Ether value sent is not correct");
      await truffleAssert.reverts(lazymint.mint(creator1.address, 1, 3, {value: 10, from:another2}), "Ether value sent is not correct");
      // Minted!
      await lazymint.mint(creator1.address, 1, 1, {value: 10, from:another2});
      await lazymint.mint(creator1.address, 1, 2, {value: 20, from:another2});
      // Too many tokens
      await truffleAssert.reverts(lazymint.mint(creator1.address, 1, 1, {value: 10, from:another2}), "Exceeded max available to purchase");
      // Sold out
      await truffleAssert.reverts(lazymint.mint(creator1.address, 1, 3, {value: 30, from:another3}), "Purchase would exceed max tokens");
      // Placeholder URI
      assert.equal("./placeholderURI" , await lazymint.tokenURI(creator1.address, 1, {from:another2}));

      // 5. Reveal
      await lazymint.reveal(creator1.address, 1, "./baseURI/", {from:another1});
      assert.equal("./baseURI/1" , await lazymint.tokenURI(creator1.address, 1, {from:another2}));
      assert.equal("./baseURI/2" , await lazymint.tokenURI(creator1.address, 2, {from:another2}));

      // 6. Withdraw
      assert.equal(3, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(30, await lazymint.totalToWithdraw(creator1.address, 1));

      const balance = await web3.eth.getBalance(anyone);
      await lazymint.withdraw(creator1.address, 1, anyone, {from:another1});
      const expectedBalance = web3.utils.toBN(balance).iadd(web3.utils.toBN(30));
      const updatedBalance = web3.utils.toBN((await web3.eth.getBalance(anyone)));
      assert.deepEqual(expectedBalance, updatedBalance);
    });

    it('multiple drops different creators', async function () {
      // 1. Create drop and configure
      await lazymint.createDrop(creator1.address, "./onePlaceholderURI", 100, 10, 1, 5, {from:another1});
      await lazymint.createDrop(creator2.address, "./twoPlaceholderURI", 100, 10, 1, 5, {from:another2});

      // 2. Set allow list
      // Creator 1
      await lazymint.setAllowList(creator1.address, 1, [another2], {from:another1});
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another2));
      // Creator 2
      await lazymint.setAllowList(creator2.address, 1, [another3], {from:another2});
      assert.equal(false, await lazymint.isInAllowList(creator2.address, 1, another2));
      assert.equal(true, await lazymint.isInAllowList(creator2.address, 1, another3));

      // 3. Activate premint
      // Creator 1
      await lazymint.activatePremintPhase(creator1.address, 1, {from:another1});
      assert.equal(1, await lazymint.salePhase(creator1.address, 1));
      assert.equal(0, await lazymint.salePhase(creator2.address, 1));
      // Creator 2
      await lazymint.activatePremintPhase(creator2.address, 1, {from:another2});
      assert.equal(1, await lazymint.salePhase(creator2.address, 1));

      // 4. Pre-mint
      // Creator 1
      await lazymint.premint(creator1.address, 1, 5, {value: 5, from:another2});
      assert.equal(5, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(0, await lazymint.totalSupply(creator2.address, 1));
      // Creator 2
      await lazymint.premint(creator2.address, 1, 5, {value: 5, from:another3});
      assert.equal(5, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(5, await lazymint.totalSupply(creator2.address, 1));

      // 5. Activate sale
      // Creator 1
      await lazymint.activateSalePhase(creator1.address, 1, {from:another1});
      assert.equal(2, await lazymint.salePhase(creator1.address, 1));
      assert.equal(1, await lazymint.salePhase(creator2.address, 1));
      // Creator 2
      await lazymint.activateSalePhase(creator2.address, 1, {from:another2});
      assert.equal(2, await lazymint.salePhase(creator1.address, 1));
      assert.equal(2, await lazymint.salePhase(creator2.address, 1));

      // 6. Mint
      // Creator 1
      await lazymint.mint(creator1.address, 1, 1, {value: 10, from:another3});
      assert.equal(6, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(5, await lazymint.totalSupply(creator2.address, 1));
      // Creator 2
      await lazymint.mint(creator2.address, 1, 3, {value: 30, from:another1});
      assert.equal(6, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(8, await lazymint.totalSupply(creator2.address, 1));

      // Check placeholder URIs are different
      // Creator 1
      assert.equal("./onePlaceholderURI" , await lazymint.tokenURI(creator1.address, 1));
      assert.equal("./onePlaceholderURI" , await lazymint.tokenURI(creator1.address, 2));
      // Creator 2
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator2.address, 1));
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator2.address, 2));

      // 7. Reveal
      // Creator 1
      await lazymint.reveal(creator1.address, 1, "./oneBaseURI/", {from:another1});
      assert.equal("./oneBaseURI/1" , await lazymint.tokenURI(creator1.address, 1));
      assert.equal("./oneBaseURI/2" , await lazymint.tokenURI(creator1.address, 2));
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator2.address, 1));
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator2.address, 2));
      // Creator 2
      await lazymint.reveal(creator2.address, 1, "./twoBaseURI/", {from:another2});
      assert.equal("./oneBaseURI/1" , await lazymint.tokenURI(creator1.address, 1));
      assert.equal("./oneBaseURI/2" , await lazymint.tokenURI(creator1.address, 2));
      assert.equal("./twoBaseURI/1" , await lazymint.tokenURI(creator2.address, 1));
      assert.equal("./twoBaseURI/2" , await lazymint.tokenURI(creator2.address, 2));

      // 8. Withdraw
      // Creator 1
      assert.equal(6, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(15, await lazymint.totalToWithdraw(creator1.address, 1));
      const balance1 = await web3.eth.getBalance(anyone);
      await lazymint.withdraw(creator1.address, 1, anyone, {from:another1});
      const expectedBalance1 = web3.utils.toBN(balance1).iadd(web3.utils.toBN(15));
      const updatedBalance1 = web3.utils.toBN((await web3.eth.getBalance(anyone)));
      assert.deepEqual(expectedBalance1, updatedBalance1);

      // Creator 2
      assert.equal(8, await lazymint.totalSupply(creator2.address, 1));
      assert.equal(35, await lazymint.totalToWithdraw(creator2.address, 1));
      const balance2 = await web3.eth.getBalance(someone);
      await lazymint.withdraw(creator2.address, 1, someone, {from:another2});
      const expectedBalance2 = web3.utils.toBN(balance2).iadd(web3.utils.toBN(35));
      const updatedBalance2 = web3.utils.toBN((await web3.eth.getBalance(someone)));
      assert.deepEqual(expectedBalance2, updatedBalance2);
    });

    it('multiple drops same creator', async function () {
      // 1. Create drop and configure
      await lazymint.createDrop(creator1.address, "./onePlaceholderURI", 100, 10, 1, 5, {from:another1});
      await lazymint.createDrop(creator1.address, "./twoPlaceholderURI", 100, 10, 1, 5, {from:another1});

      // 2. Set allow list
      // Drop 1
      await lazymint.setAllowList(creator1.address, 1, [another2], {from:another1});
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 1, another2));
      // Drop 2
      await lazymint.setAllowList(creator1.address, 2, [another3], {from:another1});
      assert.equal(false, await lazymint.isInAllowList(creator1.address, 2, another2));
      assert.equal(true, await lazymint.isInAllowList(creator1.address, 2, another3));

      // 3. Activate premint
      // Drop 1
      await lazymint.activatePremintPhase(creator1.address, 1, {from:another1});
      assert.equal(1, await lazymint.salePhase(creator1.address, 1));
      assert.equal(0, await lazymint.salePhase(creator1.address, 2));
      // Drop 2
      await lazymint.activatePremintPhase(creator1.address, 2, {from:another1});
      assert.equal(1, await lazymint.salePhase(creator1.address, 2));

      // 4. Pre-mint
      // Drop 1
      await lazymint.premint(creator1.address, 1, 5, {value: 5, from:another2});
      assert.equal(5, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(0, await lazymint.totalSupply(creator1.address, 2));
      // Drop 2
      await lazymint.premint(creator1.address, 2, 5, {value: 5, from:another3});
      assert.equal(5, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(5, await lazymint.totalSupply(creator1.address, 2));

      // 5. Activate sale
      // Drop 1
      await lazymint.activateSalePhase(creator1.address, 1, {from:another1});
      assert.equal(2, await lazymint.salePhase(creator1.address, 1));
      assert.equal(1, await lazymint.salePhase(creator1.address, 2));
      // Drop 2
      await lazymint.activateSalePhase(creator1.address, 2, {from:another1});
      assert.equal(2, await lazymint.salePhase(creator1.address, 1));
      assert.equal(2, await lazymint.salePhase(creator1.address, 2));

      // 6. Mint
      // Drop 1
      await lazymint.mint(creator1.address, 1, 1, {value: 10, from:another3});
      assert.equal(6, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(5, await lazymint.totalSupply(creator1.address, 2));
      // Drop 2
      await lazymint.mint(creator1.address, 2, 3, {value: 30, from:another1});
      assert.equal(6, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(8, await lazymint.totalSupply(creator1.address, 2));

      // Check placeholder URIs are different
      // Drop 1 (tokens 1-5 and 11 are from drop 1, 6-10 and 12-14 are drop 2)
      assert.equal("./onePlaceholderURI" , await lazymint.tokenURI(creator1.address, 1));
      assert.equal("./onePlaceholderURI" , await lazymint.tokenURI(creator1.address, 11));
      // Creator 2
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator1.address, 6));
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator1.address, 12));

      // 7. Reveal
      // Creator 1
      await lazymint.reveal(creator1.address, 1, "./oneBaseURI/", {from:another1});
      assert.equal("./oneBaseURI/1" , await lazymint.tokenURI(creator1.address, 1));
      assert.equal("./oneBaseURI/6" , await lazymint.tokenURI(creator1.address, 11));
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator1.address, 6));
      assert.equal("./twoPlaceholderURI" , await lazymint.tokenURI(creator1.address, 12));
      // Creator 2
      await lazymint.reveal(creator1.address, 2, "./twoBaseURI/", {from:another1});
      assert.equal("./oneBaseURI/1" , await lazymint.tokenURI(creator1.address, 1));
      assert.equal("./oneBaseURI/6" , await lazymint.tokenURI(creator1.address, 11));
      assert.equal("./twoBaseURI/1" , await lazymint.tokenURI(creator1.address, 6));
      assert.equal("./twoBaseURI/6" , await lazymint.tokenURI(creator1.address, 12));

      // 8. Withdraw
      // Creator 1
      assert.equal(6, await lazymint.totalSupply(creator1.address, 1));
      assert.equal(15, await lazymint.totalToWithdraw(creator1.address, 1));
      const balance1 = await web3.eth.getBalance(anyone);
      await lazymint.withdraw(creator1.address, 1, anyone, {from:another1});
      const expectedBalance1 = web3.utils.toBN(balance1).iadd(web3.utils.toBN(15));
      const updatedBalance1 = web3.utils.toBN((await web3.eth.getBalance(anyone)));
      assert.deepEqual(expectedBalance1, updatedBalance1);

      // Creator 2
      assert.equal(8, await lazymint.totalSupply(creator1.address, 2));
      assert.equal(35, await lazymint.totalToWithdraw(creator1.address, 2));
      const balance2 = await web3.eth.getBalance(someone);
      await lazymint.withdraw(creator1.address, 2, someone, {from:another1});
      const expectedBalance2 = web3.utils.toBN(balance2).iadd(web3.utils.toBN(35));
      const updatedBalance2 = web3.utils.toBN((await web3.eth.getBalance(someone)));
      assert.deepEqual(expectedBalance2, updatedBalance2);
    });
  });
});
