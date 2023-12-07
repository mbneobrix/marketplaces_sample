// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


import "./helpers/ERC2771Recipient.sol";


error PriceNotMet(address nftAddress, uint256 tokenId, uint256 unitPrice);
error ItemNotForSale(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NoProceeds();
error NotOwner();
error NotApprovedForMarketplace();
error PriceMustBeAboveZero();
error AmountGreaterThanListedAmount();

contract MarketPlaceExample is Initializable, OwnableUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ERC2771Recipient {

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct Listing {
        uint256 unitPrice;
        address seller;
        string nftType;
        uint256 amount;
    }

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        string nftType,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 unitPrice
    );

    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        string nftType,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 unitPrice
    );

    mapping(address => mapping(uint256 => Listing)) private listings;  // nftAddress => tokenId => Listing

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }


    function initialize() initializer public {
        __Pausable_init();
        __Ownable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, SUPER_ADMIN_ROLE);
    }
/*
******************************************Contract Settings Functions****************************************************
*/

    /**
    * @dev overriding the inherited {transferOwnership} function to reflect the admin changes into the {DEFAULT_ADMIN_ROLE}
    */
    
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        renounceRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    

    /**
    * @dev modifier to check super admin rights.
    * contract owner and super admin have super admin rights
    */

    modifier onlySuperAdmin() {
        require(
            hasRole(SUPER_ADMIN_ROLE, _msgSender()) ||
            owner() == _msgSender(),
            "Unauthorized Access");
        _;
    }

    /**
    * @dev modifier to check admin rights.
    * contract owner, super admin and admins have admin rights
    */
    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, _msgSender()) ||
            hasRole(SUPER_ADMIN_ROLE, _msgSender()) ||
            owner() == _msgSender(),
            "Unauthorized Access");
        _;
    }

    /**
    * @dev modifier to check pause rights.
    * contract owner, super admin and pausers's have pause rights
    */
    modifier onlyPauser() {
        require(
            hasRole(PAUSER_ROLE, _msgSender()) ||
            hasRole(SUPER_ADMIN_ROLE, _msgSender()) || 
            owner() == _msgSender(),
            "Unauthorized Access");
        _;
    }

    function pause() public onlyPauser {
        _pause();
    }

    function unpause() public onlyPauser {
        _unpause();
    }

    function addSuperAdmin(address _superAdmin) public onlyOwner {
        _grantRole(SUPER_ADMIN_ROLE, _superAdmin);
    }

    function addAdmin(address _admin) public onlySuperAdmin {
        _grantRole(ADMIN_ROLE, _admin);
    }

    function addPauser(address account) public onlySuperAdmin {
        _grantRole(PAUSER_ROLE, account);
    }

    function removeSuperAdmin(address _superAdmin) public onlyOwner {
        _revokeRole(SUPER_ADMIN_ROLE, _superAdmin);
    }

    function removeAdmin(address _admin) public onlySuperAdmin {
        _revokeRole(ADMIN_ROLE, _admin);
    }

    function removePauser(address _pauser) public onlySuperAdmin {
        _revokeRole(PAUSER_ROLE, _pauser);
    } 
/*
****************************************** MarketPlace Helpers*********************************
*/

    function isNftOwner( address nftAddress,
        uint256 tokenId,
        string memory nftType,
        address spender
    ) internal view {
    if(keccak256(abi.encodePacked(nftType)) == keccak256("ERC721")) {
            IERC721 nft = IERC721(nftAddress);
            address owner = nft.ownerOf(tokenId);
            if (spender != owner) {
                revert NotOwner();
            }
        }else if(keccak256(abi.encodePacked(nftType)) == keccak256("ERC1155")){
            IERC1155 nft = IERC1155(nftAddress);
            uint256 balance = nft.balanceOf(spender,tokenId);
            if (balance <= 0) {
                revert NotOwner();
            }
        }else{
            revert("Invalid NFT Type");
        }
   }

   function _transferNft(address _from, address _to, string memory _nftType, address _nftAddress, uint256 _nftId, uint256 _nftAmount, bytes memory _data) internal {

        if(keccak256(abi.encode(_nftType))== keccak256(abi.encode("ERC721"))){
            IERC721 exchangeAsset = IERC721(_nftAddress);
            exchangeAsset.safeTransferFrom(_from, _to, _nftId);
        }else if(keccak256(abi.encode(_nftType))== keccak256(abi.encode("ERC1155"))) {
            IERC1155 exchangeAsset = IERC1155(_nftAddress);
            exchangeAsset.safeTransferFrom(_from, _to, _nftId, _nftAmount, _data);
        } else {
            revert("Unsupported NFT Type");
        }
    }

/*
****************************************** MarketPlace Modifiers *************************************************
*/       
    modifier notListed(
        address nftAddress,
        uint256 tokenId
    ) {
        Listing memory listing = listings[nftAddress][tokenId];
        if (listing.unitPrice > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = listings[nftAddress][tokenId];
        if (listing.unitPrice <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwnerOfNft(
        address nftAddress,
        uint256 tokenId,
        string memory nftType,
        address spender
    ) {
        isNftOwner(nftAddress, tokenId, nftType, spender);
        _;
    }

    // IsNotOwner Modifier - Nft Owner can't buy his/her NFT
    // Modifies buyItem function
    // Owner should only list, cancel listing or update listing
    /* modifier isNotOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender == owner) {
            revert IsNotOwner();
        }
        _;
    } */

/*
*****************************************MarketPlace Functions *********************************************
*/
    /*
     * @notice Method for listing NFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param unitPrice sale unitPrice for each item
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        string memory nftType,
        uint256 amount,
        uint256 unitPrice
    )
        public
        isOwnerOfNft(nftAddress, tokenId, nftType, _msgSender())
        notListed(nftAddress, tokenId)
    {
        if (unitPrice <= 0) {
            revert PriceMustBeAboveZero();
        }

        if(keccak256(abi.encodePacked(nftType)) == keccak256("ERC721")) {
            IERC721 nft = IERC721(nftAddress);
            if (nft.getApproved(tokenId) != address(this)) {
                revert NotApprovedForMarketplace();
            }

            listings[nftAddress][tokenId] = Listing(unitPrice,_msgSender(), nftType, 1);

        }else if(keccak256(abi.encodePacked(nftType)) == keccak256("ERC1155")){

            if(amount <= 0) {
                revert ("0 NFTs Requested for Listing");
            }

            IERC1155 nft = IERC1155(nftAddress);

            if (nft.isApprovedForAll(_msgSender(), address(this)) == false) {
                revert NotApprovedForMarketplace();
            }

            uint256 balance = nft.balanceOf(_msgSender(),tokenId);
            if (balance < amount) {
                revert("Owner doesn't poses required No. of NFT's");
            }

            listings[nftAddress][tokenId] = Listing(unitPrice,_msgSender(), nftType, amount);

        }else {
            revert("Invalid NFT Type");
        }    

        emit ItemListed(_msgSender(), nftAddress, nftType, tokenId, amount, unitPrice);
    }

    /*
     * @notice Method for cancelling listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function cancelListing(address nftAddress, uint256 tokenId)
        external
        isListed(nftAddress, tokenId)
    {
        Listing memory listing = listings[nftAddress][tokenId];
        isNftOwner(nftAddress, tokenId, listing.nftType,_msgSender());
        delete (listings[nftAddress][tokenId]);
        emit ItemCanceled(_msgSender(), nftAddress, tokenId);
    }

    /*
     * @notice Method for buying listing
     * @notice The owner of an NFT could unapprove the marketplace,
     * which would cause this function to fail
     * Ideally you'd also have a `createOffer` functionality.
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function buyItem(address recipient, address nftAddress, uint256 tokenId, uint256 amount)
        external
        payable
        isListed(nftAddress, tokenId)
        // isNotOwner(nftAddress, tokenId,_msgSender())
        nonReentrant
    {
        Listing memory listedItem = listings[nftAddress][tokenId];

        if(amount > listedItem.amount) {
            revert AmountGreaterThanListedAmount();
        }
        
        if (msg.value < (listedItem.unitPrice * amount)) {
            revert PriceNotMet(nftAddress, tokenId, listedItem.unitPrice);
        }
        
        listedItem.amount = listedItem.amount - amount;

        if(listedItem.amount == 0)
            delete (listings[nftAddress][tokenId]);
        else
            listings[nftAddress][tokenId].amount = listedItem.amount;  

        payable(listedItem.seller).transfer(msg.value);
        _transferNft(listedItem.seller, recipient, listedItem.nftType, nftAddress, tokenId, amount, "");
        
        emit ItemBought(_msgSender(), nftAddress, listedItem.nftType, tokenId, amount , listedItem.unitPrice);
    }

    /*
     * @notice Method for updating listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param newPrice Price in Wei of the item
     */
    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    )
        external
        isListed(nftAddress, tokenId)
        nonReentrant
    {
        //We should check the value of `newPrice` and revert if it's below zero (like we also check in `listItem()`)
        if (newPrice <= 0) {
            revert PriceMustBeAboveZero();
        }
        Listing memory listing = listings[nftAddress][tokenId];
        isNftOwner(nftAddress, tokenId, listing.nftType,_msgSender());
        listings[nftAddress][tokenId].unitPrice = newPrice;
        emit ItemListed(_msgSender(), nftAddress, listing.nftType, tokenId, listing.amount, newPrice);
    }

    /////////////////////
    // Getter Functions //
    /////////////////////

    function getListing(address nftAddress, uint256 tokenId)
        external
        view
        returns (Listing memory)
    {
        return listings[nftAddress][tokenId];
    }


/*
***************************************** Important Functions - Edit With Care ***********************************************************
*/   
    function _msgSender() internal view virtual override(ContextUpgradeable, ERC2771Recipient) returns (address sender) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override(ContextUpgradeable, ERC2771Recipient) returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }
    
   receive() external payable {}
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}