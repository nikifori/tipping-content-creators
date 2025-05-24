const { expect } = require("chai");
const { ethers } = require("hardhat");

const { parseEther } = ethers;   // v6 helper → returns bigint

describe("TipWithCause", function () {
  let TipWithCause, tipWithCause;
  let owner, creator, sponsor1, sponsor2, tipper;

  beforeEach(async () => {
    [owner, creator, sponsor1, sponsor2, tipper] = await ethers.getSigners();

    TipWithCause = await ethers.getContractFactory("TipWithCause");
    tipWithCause = await TipWithCause.deploy([
      sponsor1.address,
      sponsor2.address,
    ]);
    await tipWithCause.waitForDeployment();     // v6 replacement for .deployed()
  });

  it("deploys with correct initial state", async () => {
    expect(await tipWithCause.owner()).to.equal(owner.address);
    expect(await tipWithCause.active()).to.equal(true);
    expect(await tipWithCause.getCausesCount()).to.equal(2n);
  });

  it("handles implicit 10 % donation", async () => {
    const tip      = parseEther("1");       // bigint
    const donation = tip / 10n;             // 10 %
    const creatorShare = tip - donation;

    await expect(() =>
      tipWithCause
        .connect(tipper)
        ["tip(address,uint256)"](creator.address, 0, { value: tip })
    ).to.changeEtherBalances(
      [tipper, creator, sponsor1],
      [tip * -1n, creatorShare, donation]
    );

    expect(await tipWithCause.totalTipped()).to.equal(tip);
  });

  it("handles explicit donation inside range", async () => {
    const tip      = parseEther("1");
    const donation = parseEther("0.3");     // 30 %
    const creatorShare = tip - donation;

    await expect(() =>
      tipWithCause
        .connect(tipper)
        ["tip(address,uint256,uint256)"](creator.address, 1, donation, {
          value: tip,
        })
    ).to.changeEtherBalances(
      [tipper, creator, sponsor2],
      [tip * -1n, creatorShare, donation]
    );
  });

  it("rejects donation outside allowed range", async () => {
    const tip   = parseEther("1");
    const tooLow = 0n;                      // 0 %

    await expect(
      tipWithCause
        .connect(tipper)
        ["tip(address,uint256,uint256)"](creator.address, 0, tooLow, {
          value: tip,
        })
    ).to.be.revertedWith("TipWithCause: donation outside allowed range");
  });

  it("tracks highest tip correctly", async () => {
    const tip1 = parseEther("1");
    await tipWithCause
      .connect(tipper)
      ["tip(address,uint256)"](creator.address, 0, { value: tip1 });

    const tip2 = parseEther("2");           // bigger second tip
    await tipWithCause
      .connect(tipper)
      ["tip(address,uint256)"](creator.address, 0, { value: tip2 });

    const [highestTipper, amount] = await tipWithCause.getHighestTip();
    expect(highestTipper).to.equal(tipper.address);
    expect(amount).to.equal(tip2);
  });

  it("enforces owner-only deactivate / activate guard", async () => {
    await tipWithCause.deactivate();
    expect(await tipWithCause.active()).to.equal(false);

    const tip = parseEther("1");
    await expect(
      tipWithCause
        .connect(tipper)
        ["tip(address,uint256)"](creator.address, 0, { value: tip })
    ).to.be.revertedWith("TipWithCause: contract is not active");

    await tipWithCause.activate();          // flip back on
    await tipWithCause
      .connect(tipper)
      ["tip(address,uint256)"](creator.address, 0, { value: tip });
  });

  it("blocks getHighestTip for non-owners", async () => {
    await expect(
      tipWithCause.connect(tipper).getHighestTip()
    ).to.be.revertedWith("TipWithCause: caller is not the owner");
  });
});
