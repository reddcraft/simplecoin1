pragma solidity ^0.4.8;

import "ds-test/test.sol";
import "ds-token/base.sol";
import "ds-feeds/feeds.sol";

import "./simplecoin.sol";
import "./simplecoin_factory.sol";

contract SimplecoinTest is DSTest {
    // Be explicit about units. Can force this by setting to prime
    // powers, but then percentage changes are difficult.
    uint constant COL1 = 1;
    uint constant COIN = 1;

    Simplecoin   coin;
    DSFeeds      feeds;
    Vault        vault;
    DSTokenBase  col1;
    uint48       icol1;
    bytes12      feed1;

    function setUp() {
        feeds = new DSFeeds();

        coin = new Simplecoin(feeds, "Test Coin Token", "TCT");

        col1 = new DSTokenBase(10**24 * COL1);
        col1.approve(coin, 10**24 * COL1);

        feed1 = feeds.claim();
        // set price to 0.1 simplecoins per unit of col1
        var price = (coin.PRICE_UNIT() * COL1) / (10 * COIN);
        feeds.set(feed1, bytes32(price), uint40(block.timestamp + 10));

        vault = new Vault();
        vault.approve(col1, coin, uint(-1));  // pragma: no audit

        icol1 = coin.register(col1);
        coin.setVault(icol1, vault);
        coin.setFeed(icol1, feed1);
        coin.setSpread(icol1, 1000); // 0.1% either way
    }

    function testAuthSetup() {
        assertEq(coin.authority(), this);
    }

    function testBasics() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);

        var obtained = coin.issue(icol1, 100000 * COL1);

        assertEq(obtained, 999000 * COIN);
        assertEq(obtained, coin.balanceOf(this));

        var before = col1.balanceOf(this);
        var returned = coin.cover(icol1, coin.balanceOf(this));
        var afterward = col1.balanceOf(this);  // `after` is a keyword??

        assertEq(returned, afterward - before);
        assertEq(returned, 99800 * COL1); // minus 0.2%
    }

    function testIssueTransferFromCaller() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;

        var balance_before = col1.balanceOf(this);
        var obtained = coin.issue(icol1, collateral_spend);
        assertEq(balance_before - col1.balanceOf(this), collateral_spend);
    }

    function testIssueTransferToVault() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;

        var balance_before = col1.balanceOf(vault);
        var obtained = coin.issue(icol1, collateral_spend);
        assertEq(col1.balanceOf(vault) - balance_before, collateral_spend);
    }

    function testIssueTransferToCaller() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;

        var balance_before = coin.balanceOf(this);
        var obtained = coin.issue(icol1, collateral_spend);
        var balance_after = coin.balanceOf(this);

        assertEq(balance_after - balance_before, 999000 * COIN);
    }

    function testIssueCreatesCoin() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;

        var supply_before = coin.totalSupply();
        var obtained = coin.issue(icol1, collateral_spend);
        var supply_after = coin.totalSupply();

        assertEq(supply_after - supply_before, 999000 * COIN);
    }

    function testCoverTransferToCaller() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;
        var obtained = coin.issue(icol1, collateral_spend);

        var balance_before = col1.balanceOf(this);
        var returned = coin.cover(icol1, obtained);
        var balance_after = col1.balanceOf(this);

        assertEq(balance_after - balance_before, returned);
        assertEq(balance_after - balance_before, 99800 * COL1);
    }

    function testCoverTransferFromVault() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;
        var obtained = coin.issue(icol1, collateral_spend);

        var balance_before = col1.balanceOf(vault);
        var returned = coin.cover(icol1, obtained);
        var balance_after = col1.balanceOf(vault);

        assertEq(balance_before - balance_after, 99800 * COL1);
    }

    function testCoverTransferFromCaller() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;
        var obtained = coin.issue(icol1, collateral_spend);

        var balance_before = coin.balanceOf(this);
        var returned = coin.cover(icol1, obtained);
        var balance_after = coin.balanceOf(this);

        assertEq(balance_before - balance_after, 999000 * COIN);
    }

    function testCoverDestroysCoin() {
        coin.setCeiling(icol1, 10 ** 6 * COIN);
        var collateral_spend = 100000 * COL1;
        var obtained = coin.issue(icol1, collateral_spend);

        var supply_before = coin.totalSupply();
        var returned = coin.cover(icol1, obtained);
        var supply_after = coin.totalSupply();

        assertEq(supply_before - supply_after, 999000 * COIN);
    }
}

contract SimpleAuthTest is DSTest {
    Simplecoin coin;
    SimplecoinFactory factory;

    DSFeeds feeds;
    Vault vault;

    FakePerson admin;
    FakePerson issuer;
    FakePerson holder;

    DSTokenBase _token;
    uint48 _id;

    bytes12 feed;

    function setUp() {
        factory = new SimplecoinFactory();
        feeds = new DSFeeds();

        coin = factory.create(feeds, "Test Coin Token", "TCT");
        _token = new DSTokenBase(1000);

        admin = new FakePerson(coin);
        issuer = new FakePerson(coin);
        holder = new FakePerson(coin);

        SimpleRoleAuth(coin.authority()).addAdmin(admin);
        SimpleRoleAuth(coin.authority()).addIssuer(issuer);
        SimpleRoleAuth(coin.authority()).addHolder(holder);

        _id = coin.register(_token);
        _token.transfer(admin, 100);
        _token.transfer(holder, 100);
        _token.transfer(issuer, 100);

        var feed = feeds.claim();
        // set price to 1:1, never expire
        feeds.set(feed, bytes32(coin.PRICE_UNIT()), uint40(-1));
        coin.setFeed(_id, feed);

        vault = new Vault();
        vault.approve(_token, coin, uint(-1));
        coin.setVault(_id, vault);

        coin.setSpread(_id, uint(-1));     // 0% cut
        coin.setCeiling(_id, uint(-1));  // no debt limit

        //We need to allow the coin to transfer _token from the issuer
        issuer.approve(_token, coin, uint(-1));
    }
    
    function testSetUp() {
        // we own the authority
        assertEq(SimpleRoleAuth(coin.authority()).authority(), address(this));    
    }

    function testCreatorCanTransferOwnership() {
        FakePerson newOwner = new FakePerson(coin);
        SimpleRoleAuth(coin.authority()).setAuthority(DSIAuthority(newOwner));
        assertEq(SimpleRoleAuth(coin.authority()).authority(), newOwner);
    }
   
    function testAdminCanRegister() {
        var token = new DSTokenBase(1000);
        var id = admin.register(token);
        assertEq(coin.token(id), token);
    }
    
    function testFailIssuerRegister() {
        var token = new DSTokenBase(1000);
        issuer.register(token);
    }

    function testFailHolderRegister() {
        var token = new DSTokenBase(1000);
        holder.register(token);
    }

    function testAdminCanSetVault() {
        admin.setVault(_id, 0x123);
        assertEq(coin.vault(_id), 0x123);
    }

    function testFailIssuerSetVault() {
        Simplecoin(issuer).setVault(_id, 0x123);
    }
    function testFailHolderSetVault() {
        Simplecoin(holder).setVault(_id, 0x123);
    }

    function testAdminCanSetFeed() {
        admin.setFeed(_id, 123);
        assertEq(uint(coin.feed(_id)), 123);
    }
    function testFailIssuerSetFeed() {
        issuer.setFeed(_id, 123);
    }
    function testFailHolderSetFeed() {
        holder.setFeed(_id, 123);
    }

    function testAdminCanSetSpread() {
        admin.setSpread(_id, 1000);
        assertEq(coin.spread(_id), 1000);
    }
    function testFailIssuerSetSpread() {
        issuer.setSpread(_id, 1000);
    }
    function testFailHolderSetSpread() {
        holder.setSpread(_id, 1000);
    }

    function testAdminCanSetCeiling() {
        admin.setCeiling(_id, 1000);
        assertEq(coin.ceiling(_id), 1000);
    }
    function testFailIssuerSetCeiling() {
        issuer.setCeiling(_id, 1000);
    }
    function testFailHolderSetCeiling() {
        holder.setCeiling(_id, 1000);
    }

    function testAdminCanUnregister() {
        admin.unregister(_id);
        assertEq(coin.token(_id), 0);
    }
    function testFailIssuerUnregister() {
        issuer.unregister(_id);
    }
    function testFailHolderUnregister() {
        holder.unregister(_id);
    }

    function testIssuerCanIssue() {
        issuer.issue(_id, 100);
        assertEq(coin.balanceOf(issuer), 100);
    }
    function testIssuerCanCover() {
        issuer.issue(_id, 100);
        issuer.cover(_id, 100);
    }
    function testFailHolderIssue() {
        holder.issue(_id, 100);
    }
    function testFailHolderCover() {
        issuer.issue(_id, 100);
        holder.cover(_id, 100);
    }

    function testHolderCanReceive() {
        issuer.issue(_id, 100);
        issuer.transfer(holder, 100);
        assertEq(coin.balanceOf(holder), 100);
    }
    function testHolderCanTransfer() {
        issuer.issue(_id, 100);
        issuer.transfer(holder, 50);
        holder.transfer(admin, 25);
    }
    function testFailNonHolderReceive() {
        FakePerson unauthorised = new FakePerson(coin);
        issuer.issue(_id, 100);
        issuer.transfer(holder, 50);
        holder.transfer(unauthorised, 25);
    }
    function testFailNonHolderTransfer() {
        FakePerson unauthorised = new FakePerson(coin);

        issuer.issue(_id, 100);
        issuer.approve(coin, unauthorised, 100);
        unauthorised.transferFrom(issuer, holder, 25);
    }
}

contract Vault {
    function approve(ERC20 token, address who, uint how_much) {
        token.approve(who, how_much);
    }
}

contract FakePerson {
    Simplecoin coin;

    function FakePerson(Simplecoin coin_) {
        coin  = coin_;
    }

    function register(ERC20 token) returns (uint48) {
        return coin.register(token);
    }

    function unregister(uint48 id) {
        coin.unregister(id);
    }

    function approve(ERC20 token, address who, uint how_much) {
        token.approve(who, how_much);
    }

    function setVault(uint48 id, address addr) {
        coin.setVault(id, addr);
    }

    function setFeed(uint48 id, bytes12 feed) {
        coin.setFeed(id, feed);
    }

    function setSpread(uint48 id, uint spread) {
        coin.setSpread(id, spread);
    }

    function setCeiling(uint48 id, uint ceiling) {
        coin.setCeiling(id, ceiling);
    }

    function issue(uint48 id, uint amount) {
        coin.issue(id, amount);
    }

    function cover(uint48 id, uint amount) {
        coin.cover(id, amount);
    }

    function transfer(address addr, uint amount) {
        coin.transfer(addr, amount);
    }

    function transferFrom(address from, address to, uint amount) {
        coin.transferFrom(from, to, amount);
    }
}
