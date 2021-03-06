const { EtherscanProvider } = require("@ethersproject/providers");
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe('Royalty Manager Contract', ()=> {
    var deployerAddress, testManagerAddress, creatorAddress, playerAddress, staker1;

    var resolver;
    var contentFactory;
    var content;
    var contentManager;

    var rawrToken;
    var royaltyManager;
    var executionManager;
    var escrow;
    const _1e18 = ethers.BigNumber.from('10').pow(ethers.BigNumber.from('18'));

    before(async () => {
        [deployerAddress, testManagerAddress, creatorAddress, playerAddress, staker1] = await ethers.getSigners();

        AccessControlManager = await ethers.getContractFactory("AccessControlManager");
        ContentStorage = await ethers.getContractFactory("ContentStorage");
        Content = await ethers.getContractFactory("Content");
        ContentManager = await ethers.getContractFactory("ContentManager");
        ContentFactory = await ethers.getContractFactory("ContentFactory");
        AddressResolver = await ethers.getContractFactory("AddressResolver");
        MockToken = await ethers.getContractFactory("MockToken");
        MockStaking = await ethers.getContractFactory("MockStaking");
        Erc20Escrow = await ethers.getContractFactory("Erc20Escrow");
        ExecutionManager = await ethers.getContractFactory("ExecutionManager");
        ExchangeFeesEscrow = await ethers.getContractFactory("ExchangeFeesEscrow");
        RoyaltyManager = await ethers.getContractFactory("RoyaltyManager");

        originalAccessControlManager = await AccessControlManager.deploy();
        originalContent = await Content.deploy();
        originalContentStorage = await ContentStorage.deploy();
        originalContentManager = await ContentManager.deploy();
    
        // Initialize Clone Factory
        contentFactory = await upgrades.deployProxy(ContentFactory, [originalContent.address, originalContentManager.address, originalContentStorage.address, originalAccessControlManager.address]);
        
        resolver = await upgrades.deployProxy(AddressResolver, []);
    });


    async function ContentContractSetup() {
        var tx = await contentFactory.createContracts(creatorAddress.address, 20000, "arweave.net/tx-contract-uri");
        var receipt = await tx.wait();
        var deployedContracts = receipt.events?.filter((x) => {return x.event == "ContractsDeployed"});

        // To figure out which log contains the ContractDeployed event
        content = await Content.attach(deployedContracts[0].args.content);
        contentManager = await ContentManager.attach(deployedContracts[0].args.contentManager);
            
        // Add 2 assets
        var asset = [
            ["arweave.net/tx/public-uri-0", "arweave.net/tx/private-uri-0", ethers.constants.MaxUint256, deployerAddress.address, 20000],
            ["arweave.net/tx/public-uri-1", "arweave.net/tx/private-uri-1", 100, ethers.constants.AddressZero, 0]
        ];

        await contentManager.addAssetBatch(asset);
    }

    async function RawrTokenSetup() {
        // Setup RAWR token
        rawrToken = await upgrades.deployProxy(MockToken, ["Rawrshak Token", "RAWR"]);
        await rawrToken.mint(deployerAddress.address, ethers.BigNumber.from(100000000).mul(_1e18));
        
        // Give player 1 20000 RAWR tokens
        await rawrToken.transfer(playerAddress.address, ethers.BigNumber.from(20000).mul(_1e18));
    }

    async function RoyaltyManagerSetup() {
        staking = await MockStaking.deploy(resolver.address);
        await feesEscrow.registerManager(staking.address);
        
        // register the royalty manager
        await resolver.registerAddress(["0x29a264aa", "0x7f170836", "0x1b48faca"], [escrow.address, feesEscrow.address, staking.address]);
        
        await staking.connect(staker1).stake(ethers.BigNumber.from(100).mul(_1e18));
        await feesEscrow.setRate(3000);

        // Register the royalty manager
        await escrow.registerManager(royaltyManager.address);
        await feesEscrow.registerManager(royaltyManager.address);
        
        // Testing manager to create fake data
        await escrow.registerManager(testManagerAddress.address)
        await feesEscrow.registerManager(testManagerAddress.address);

        // add token support
        await escrow.connect(testManagerAddress).addSupportedTokens(rawrToken.address);
    }

    beforeEach(async () => {
        escrow = await upgrades.deployProxy(Erc20Escrow, []); 
        feesEscrow = await upgrades.deployProxy(ExchangeFeesEscrow, [resolver.address]); 
        royaltyManager = await upgrades.deployProxy(RoyaltyManager, [resolver.address]);
    });
    
    describe("Basic Tests", () => {
        it('Check if Royalty Manager was deployed properly', async () => {
            expect(royaltyManager.address).not.equal(ethers.constants.AddressZero);
        });
    
        it('Supports the Royalty Manager Interface', async () => {
            // IRoyaltyManager Interface
            expect(await royaltyManager.supportsInterface("0x93881355")).to.equal(true);
        });
    });
    
    describe("Functional Tests", () => {
        it('Deposit Royalty from buyer to royalty receiver', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();
    
            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(230).mul(_1e18));
            await royaltyManager['transferRoyalty(address,address,address,uint256)'](playerAddress.address, rawrToken.address, creatorAddress.address, ethers.BigNumber.from(200).mul(_1e18));
    
            var claimable = await escrow.connect(creatorAddress).claimableTokensByOwner(creatorAddress.address);
            expect(claimable.amounts[0]).to.equal(ethers.BigNumber.from(200).mul(_1e18));
    
            await royaltyManager['transferPlatformFee(address,address,uint256)'](playerAddress.address, rawrToken.address, ethers.BigNumber.from(10000).mul(_1e18));
    
            expect(await rawrToken.balanceOf(feesEscrow.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
            expect(await feesEscrow.totalFees(rawrToken.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
        });
        
        it('Transfer Royalty from single orderId to royalty owner', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();

            // deposit 10000 RAWR tokens for Order 1 
            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(10000).mul(_1e18));
            await escrow.connect(testManagerAddress).deposit(rawrToken.address, 1, playerAddress.address, ethers.BigNumber.from(10000).mul(_1e18));

            await royaltyManager['transferRoyalty(uint256,address,uint256)'](1, creatorAddress.address, ethers.BigNumber.from(200).mul(_1e18));
            await royaltyManager['transferPlatformFee(address,uint256,uint256)'](rawrToken.address, 1, ethers.BigNumber.from(10000).mul(_1e18));

            claimable = await escrow.connect(creatorAddress).claimableTokensByOwner(creatorAddress.address);
            expect(claimable.amounts[0]).to.equal(ethers.BigNumber.from(200).mul(_1e18));
            
            // check if amounts were moved from the escrow for the order to claimable for the creator
            expect(await escrow.escrowedTokensByOrder(1)).to.equal(ethers.BigNumber.from(9770).mul(_1e18));
            
            expect(await rawrToken.balanceOf(feesEscrow.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
            expect(await escrow.escrowedTokensByOrder(1)).to.equal(ethers.BigNumber.from(9770).mul(_1e18));
            expect(await feesEscrow.totalFees(rawrToken.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
        });

        it('Transfer Royalties from multiple orderIds to claimable', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();

            var amounts = [ethers.BigNumber.from(5000).mul(_1e18), ethers.BigNumber.from(5000).mul(_1e18)];
            var royaltyFees = [ethers.BigNumber.from(100).mul(_1e18), ethers.BigNumber.from(100).mul(_1e18)];
            var platformFees = [ethers.BigNumber.from(15).mul(_1e18), ethers.BigNumber.from(15).mul(_1e18)];
            
            // deposit 5000 RAWR tokens for Order 1 & 2
            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(10000).mul(_1e18));
            await escrow.connect(testManagerAddress).depositBatch(rawrToken.address, [1, 2], playerAddress.address, amounts);

            await royaltyManager.transferRoyalties([1, 2], creatorAddress.address, royaltyFees);
            await royaltyManager.transferPlatformFees(rawrToken.address, [1, 2], platformFees);

            claimable = await escrow.connect(creatorAddress).claimableTokensByOwner(creatorAddress.address);
            expect(claimable.amounts[0]).to.equal(ethers.BigNumber.from(200).mul(_1e18));
            
            // check if amounts were moved from the escrow for the order to claimable for the creator
            expect(await escrow.escrowedTokensByOrder(1)).to.equal(ethers.BigNumber.from(4885).mul(_1e18));
            expect(await escrow.escrowedTokensByOrder(2)).to.equal(ethers.BigNumber.from(4885).mul(_1e18));
            expect(await rawrToken.balanceOf(feesEscrow.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
            expect(await feesEscrow.totalFees(rawrToken.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
        });
        
        it('Get Royalties for a Single Order', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();
            
            var assetData = [content.address, 1];
            var amountPerOrder = ethers.BigNumber.from(8000).mul(_1e18);
            var results = await royaltyManager.payableRoyalties(assetData, amountPerOrder);

            expect(results.receiver).to.equal(creatorAddress.address);
            expect(results.royaltyFee).to.equal(ethers.BigNumber.from(160).mul(_1e18));
            expect(results.remaining).to.equal(ethers.BigNumber.from(7816).mul(_1e18));
        });

        it('Get Royalties for a Buy Order', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();
            
            var assetData = [content.address, 1];
            var amountPerOrder = [ethers.BigNumber.from(10000).mul(_1e18), ethers.BigNumber.from(9000).mul(_1e18)];
            var results = await royaltyManager.buyOrderRoyalties(assetData, amountPerOrder);

            expect(results.receiver).to.equal(creatorAddress.address);
            expect(results.royaltyFees.length).to.equal(2);
            expect(results.royaltyFees[0]).to.equal(ethers.BigNumber.from(200).mul(_1e18));
            expect(results.royaltyFees[1]).to.equal(ethers.BigNumber.from(180).mul(_1e18));
            expect(results.platformFees.length).to.equal(2);
            expect(results.platformFees[0]).to.equal(ethers.BigNumber.from(30).mul(_1e18));
            expect(results.platformFees[1]).to.equal(ethers.BigNumber.from(27).mul(_1e18));
            expect(results.remaining.length).to.equal(2);
            expect(results.remaining[0]).to.equal(ethers.BigNumber.from(9770).mul(_1e18));
            expect(results.remaining[1]).to.equal(ethers.BigNumber.from(8793).mul(_1e18));
        });

        it('Get Royalties for a Sell Order', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();
            
            var assetData = [content.address, 1];
            var amountPerOrder = [ethers.BigNumber.from(10000).mul(_1e18), ethers.BigNumber.from(10000).mul(_1e18)];
            var results = await royaltyManager.sellOrderRoyalties(assetData, amountPerOrder);

            expect(results.receiver).to.equal(creatorAddress.address);
            expect(results.royaltyTotal).to.equal(ethers.BigNumber.from(400).mul(_1e18));
            expect(results.remaining.length).to.equal(2);
            expect(results.remaining[0]).to.equal(ethers.BigNumber.from(9770).mul(_1e18));
            expect(results.remaining[1]).to.equal(ethers.BigNumber.from(9770).mul(_1e18));
        });

        it('Claim Royalties', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();
    
            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(300).mul(_1e18));
            await royaltyManager['transferRoyalty(address,address,address,uint256)'](playerAddress.address, rawrToken.address, creatorAddress.address, ethers.BigNumber.from(200).mul(_1e18));
    
            // claim royalties
            await royaltyManager.claimRoyalties(creatorAddress.address);
    
            var claimable = await royaltyManager.connect(creatorAddress).claimableRoyalties(creatorAddress.address);
            expect(claimable.amounts.length).to.equal(0);
        });

        it('Deposit Platform fee from buyer', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();

            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(30).mul(_1e18));
            await royaltyManager['transferPlatformFee(address,address,uint256)'](playerAddress.address, rawrToken.address, ethers.BigNumber.from(10000).mul(_1e18));
            
            // escrow should have received the fees
            expect(await feesEscrow.totalFees(rawrToken.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
            expect(await rawrToken.balanceOf(feesEscrow.address)).to.equal(ethers.BigNumber.from(30).mul(_1e18));
            // playeraddress should have had the fees deducted from their balance
            expect(await rawrToken.balanceOf(playerAddress.address)).to.equal(ethers.BigNumber.from(19970).mul(_1e18));
        });

        it('Transfer Platform fee from single orderId', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();

            // deposit tokens to escrow
            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(5000).mul(_1e18));
            await escrow.connect(testManagerAddress).deposit(rawrToken.address, [0], playerAddress.address, ethers.BigNumber.from(5000).mul(_1e18));
            
            // check that escrow has the tokens
            expect(await escrow.escrowedTokensByOrder(0)).to.equal(ethers.BigNumber.from(5000).mul(_1e18));
            expect(await rawrToken.balanceOf(escrow.address)).to.equal(ethers.BigNumber.from(5000).mul(_1e18));

            await royaltyManager['transferPlatformFee(address,uint256,uint256)'](rawrToken.address, [0], ethers.BigNumber.from(5000).mul(_1e18));

            // check to see if the tokens have been updated/switched hands
            expect(await escrow.escrowedTokensByOrder(0)).to.equal(ethers.BigNumber.from(4985).mul(_1e18));
            expect(await rawrToken.balanceOf(feesEscrow.address)).to.equal(ethers.BigNumber.from(15).mul(_1e18));
        });

        it('Transfer Platform fee from multiple orderIds', async () => {
            await ContentContractSetup();
            await RawrTokenSetup();
            await RoyaltyManagerSetup();

            // deposit tokens to escrow
            var tokenAmount = ethers.BigNumber.from(10000).mul(_1e18);
            await rawrToken.connect(playerAddress).approve(escrow.address, ethers.BigNumber.from(20000).mul(_1e18));
            await escrow.connect(testManagerAddress).depositBatch(rawrToken.address, [0, 1], playerAddress.address, [tokenAmount, tokenAmount]);
            
            // check that escrow has the tokens
            expect(await escrow.escrowedTokensByOrder(0)).to.equal(tokenAmount);
            expect(await escrow.escrowedTokensByOrder(1)).to.equal(tokenAmount);
            expect(await rawrToken.balanceOf(escrow.address)).to.equal(ethers.BigNumber.from(20000).mul(_1e18));

            await royaltyManager.transferPlatformFees(rawrToken.address, [0, 1], [ethers.BigNumber.from(30).mul(_1e18), ethers.BigNumber.from(30).mul(_1e18)]);

            // check to see if the tokens have been updated/switched hands
            expect(await escrow.escrowedTokensByOrder(0)).to.equal(ethers.BigNumber.from(9970).mul(_1e18));
            expect(await escrow.escrowedTokensByOrder(1)).to.equal(ethers.BigNumber.from(9970).mul(_1e18));
            expect(await feesEscrow.totalFees(rawrToken.address)).to.equal(ethers.BigNumber.from(60).mul(_1e18));
            expect(await rawrToken.balanceOf(feesEscrow.address)).to.equal(ethers.BigNumber.from(60).mul(_1e18));
        });
    });
});
