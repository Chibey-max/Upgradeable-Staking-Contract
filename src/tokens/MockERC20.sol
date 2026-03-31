// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
// MockERC20
// Minimal ERC-20 with mint and burn for use in tests.
// Serves as stakeToken, rewardToken, and receiptToken depending on deployment.
// ─────────────────────────────────────────────────────────────────────────────

contract MockERC20 {

    string  public name;
    string  public symbol;
    uint8   public decimals;
    uint256 public totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Minter role — set to deployer; add the Diamond after init
    mapping(address => bool) public isMinter;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply) {
        name     = _name;
        symbol   = _symbol;
        decimals = _decimals;
        owner    = msg.sender;
        isMinter[msg.sender] = true;
        _mint(msg.sender, _initialSupply);
    }

    // ── ERC-20 ─────────────────────────────────────────────────────────────

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ERC20: insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // ── Mint / Burn ────────────────────────────────────────────────────────

    function mint(address to, uint256 amount) external returns (bool) {
        require(isMinter[msg.sender], "MockERC20: not minter");
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external {
        require(isMinter[msg.sender], "MockERC20: not minter");
        require(balanceOf[from] >= amount, "MockERC20: burn exceeds balance");
        balanceOf[from] -= amount;
        totalSupply      -= amount;
        emit Transfer(from, address(0), amount);
    }

    // ── Admin ──────────────────────────────────────────────────────────────

    function addMinter(address minter) external {
        require(msg.sender == owner, "MockERC20: not owner");
        isMinter[minter] = true;
    }

    // ── Internal ───────────────────────────────────────────────────────────

    function _mint(address to, uint256 amount) internal {
        totalSupply      += amount;
        balanceOf[to]    += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
    }
}
