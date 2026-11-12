// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Riftera — Rifters (BNB Chain)
/// @notice 1,111 fantasy hero NFTs in two parallel lanes, both gated by the
///         Binance Agent ID (.ai) NFT registry:
///         - FREE lane: IDs 1..444, 0 BNB, max 3 per wallet, Common only.
///         - PAID lane: IDs 1001..1667, exactly 0.001 BNB each, max 5 per wallet,
///           the only lane that can reveal Rare / Legendary Rifters.
///         Rarity lives in the pre-generated metadata (paid IDs are pre-shuffled:
///         467 Common / 167 Rare / 33 Legendary), revealed at mint.
///         Metadata layout under baseURI: free/<id>.json and paid/<id>.json.
contract Riftera {
    string public constant name = "Riftera Rifters";
    string public constant symbol = "RIFT";
    uint256 public constant MAX_SUPPLY = 1111;
    uint256 public constant FREE_SUPPLY = 444;
    uint256 public constant PAID_SUPPLY = 667;
    uint256 public constant PAID_ID_BASE = 1000;
    uint256 public constant PAID_PRICE = 0.001 ether;
    uint256 public constant MAX_FREE_PER_WALLET = 3;
    uint256 public constant MAX_PAID_PER_WALLET = 5;

    /// Binance Agent ID (.ai) registry — constructor arg.
    /// Mainnet: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
    IAgentIdRegistry public immutable agentId;

    address public owner;
    string public baseURI;
    bool public mintOpen;
    uint256 public freeMinted;
    uint256 public paidMinted;

    mapping(address => uint256) public freeCountOf;
    mapping(address => uint256) public paidCountOf;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed tokenOwner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed tokenOwner, address indexed operator, bool approved);
    event MintOpenChanged(bool open);
    event BaseURIChanged(string newBaseURI);
    event FreeMint(address indexed minter, uint256 indexed tokenId);
    event PaidMint(address indexed minter, uint256 indexed tokenId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address agentId_, string memory baseURI_) {
        require(agentId_ != address(0), "Zero registry");
        agentId = IAgentIdRegistry(agentId_);
        owner = msg.sender;
        baseURI = baseURI_;
    }

    // ---------- ERC-165 ----------
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    // ---------- Views ----------
    function totalMinted() public view returns (uint256) {
        return freeMinted + paidMinted;
    }

    function balanceOf(address account) public view returns (uint256) {
        require(account != address(0), "Zero address");
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address a = _owners[tokenId];
        require(a != address(0), "Nonexistent token");
        return a;
    }

    function isPaidId(uint256 tokenId) public pure returns (bool) {
        return tokenId > PAID_ID_BASE;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        string memory lane = isPaidId(tokenId) ? "paid/" : "free/";
        return string(abi.encodePacked(baseURI, lane, _toString(tokenId), ".json"));
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function hasAgentId(address account) public view returns (bool) {
        return agentId.balanceOf(account) > 0;
    }

    // ---------- Mint ----------
    function mintFree() external {
        require(mintOpen, "Mint closed");
        require(hasAgentId(msg.sender), "Needs Binance Agent ID");
        require(freeMinted < FREE_SUPPLY, "Free lane sold out");
        require(freeCountOf[msg.sender] < MAX_FREE_PER_WALLET, "Free limit 3 per wallet");
        freeMinted++;
        freeCountOf[msg.sender]++;
        uint256 tokenId = freeMinted; // 1..444
        _mint(msg.sender, tokenId);
        emit FreeMint(msg.sender, tokenId);
    }

    function mintPaid() external payable {
        require(mintOpen, "Mint closed");
        require(hasAgentId(msg.sender), "Needs Binance Agent ID");
        require(msg.value == PAID_PRICE, "Pay exact 0.001 BNB");
        require(paidMinted < PAID_SUPPLY, "Paid lane sold out");
        require(paidCountOf[msg.sender] < MAX_PAID_PER_WALLET, "Paid limit 5 per wallet");
        paidMinted++;
        paidCountOf[msg.sender]++;
        uint256 tokenId = PAID_ID_BASE + paidMinted; // 1001..1667
        _mint(msg.sender, tokenId);
        emit PaidMint(msg.sender, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal {
        _owners[tokenId] = to;
        _balances[to]++;
        emit Transfer(address(0), to, tokenId);
    }

    // ---------- Transfers ----------
    function approve(address approved, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = approved;
        emit Approval(tokenOwner, approved, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, ""), "Receiver rejected");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external {
        transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "Receiver rejected");
    }

    // ---------- Owner ----------
    function setMintOpen(bool open_) external onlyOwner {
        mintOpen = open_;
        emit MintOpenChanged(open_);
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "Nothing to withdraw");
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "Withdraw failed");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ---------- Internals ----------
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return spender == tokenOwner
            || _tokenApprovals[tokenId] == spender
            || _operatorApprovals[tokenOwner][spender];
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "From not owner");
        require(to != address(0), "Zero address");
        delete _tokenApprovals[tokenId];
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private returns (bool) {
        if (to.code.length == 0) return true;
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

interface IAgentIdRegistry {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}
