// SPDX-License-Identifier: Unlicensed

// This is a work in progress.  All elements are subject to change.
pragma solidity 0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./ConstantsAF.sol";
import "./IAFCharacter.sol";
import "./AFRoles.sol";
import "./IERC2981.sol";
import "./console.sol";
import "./ECDSA.sol";

contract AdultFantasySeasonOne is ERC721, ERC721Enumerable, ERC721URIStorage, AFRoles, Ownable, IERC2981{
 
  using ECDSA for bytes32;

  uint256 public priceWEI;

  // Before this time, no minting can take place
  uint256 public mintStartTime;
    

  // All cards that have been minted
  mapping (uint256 => MintedCard) public mintedCards;

  // Represents a minted card that is owned by a user
  struct MintedCard {
    uint256 characterID;
    uint256 specialSauceCode;
    uint256 serial_numerator;
  }

  string public customBaseURI;

  string public licenseAgreementURI;

  address public royaltyTarget;

  uint256 public reservedCardsAvailable = 1000;

  // Reference to the character contract
  IAFCharacter afCharacter;  
  
  address _signingAddress;

  address public contractIdentifier;

  uint public boardingGroup = 0;

  enum MintMethods{ Whitelist, Giveaway, Reserved }

  mapping(string => bool) usedMintPasses;

  function _beforeTokenTransfer(address from, address to, uint256 tokenId)
      internal
      override(ERC721, ERC721Enumerable)
  {
      super._beforeTokenTransfer(from, to, tokenId);
  }

  function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
      super._burn(tokenId);
  }

  function tokenURI(uint256 tokenId)
      public
      view
      override(ERC721, ERC721URIStorage)
      returns (string memory)
  {
      return super.tokenURI(tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
      public
      view
      override(ERC721, ERC721Enumerable, AccessControlEnumerable)
      returns (bool)
  {
      return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
  }

  function _baseURI() internal view override returns (string memory) {
      return customBaseURI;
  }

  function royaltyInfo(
      uint256 _tokenId,
      uint256 _salePrice
  ) external view override returns (
      address receiver,
      uint256 royaltyAmount
  ) {
    return (royaltyTarget, (_salePrice *15) / 200); // To get 7.5%
  }

  constructor (address characterContractAddress, address signingAddress)
  ERC721("AdultFantasySeasonOne","AFC")
  {
    afCharacter = IAFCharacter(characterContractAddress);
    _signingAddress = signingAddress;
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  function purchaseTokenMintPass(MintMethods mintMethod,uint256 messageBoardingGroup, string memory guid, bytes memory signature) external payable{
    require(isValidAccessMessage(mintMethod, messageBoardingGroup, guid, msg.sender, signature), "Invalid token");
    require(!usedMintPasses[guid], "Token has been used");
    require (messageBoardingGroup<= boardingGroup, "This boarding group is not yet active");
    usedMintPasses[guid] = true;

    uint256 cost = 0 wei;
    if(mintMethod == MintMethods.Whitelist){ //Otherwise free+gas
      cost = priceWEI;
    }

    if(mintMethod == MintMethods.Reserved || mintMethod == MintMethods.Giveaway ){ //Ensuring we haven't minted more than the max reserved count
      require(reservedCardsAvailable >= 5); //remaining are special characters
      reservedCardsAvailable--;
    }
    
    require(msg.value == cost, ConstantsAF.incorrectAmount_e);
    mintMultiple(1, msg.sender);
  }

  function batchPurchaseReservedTokenMintPass(string[] memory guids, uint256[] memory boardingGroups, bytes[] memory signatures, address recipient) external payable{
    require(guids.length == signatures.length, "Guid length doesn't match signatures");
    require(boardingGroups.length == signatures.length, "Boarding groups length doesn't match signatures");

    //Ensuring we haven't minted more than the max reserved count
    require(reservedCardsAvailable - guids.length >= 0, "Not enough reserved cards available");
    reservedCardsAvailable-=guids.length;

    for(uint256 index = 0; index < guids.length; index++){ // validating mint passes
      string memory guid = guids[index];
      bytes memory signature = signatures[index];
      uint256 messageBoardingGroup = boardingGroups[index];
      require(isValidAccessMessage(MintMethods.Reserved,messageBoardingGroup, guid, recipient, signature), "Access message is invalid");
      require(!usedMintPasses[guid], "Mint pass is used");
      require (boardingGroups[index] <= boardingGroup, "This boarding group is not yet active");
      usedMintPasses[guid] = true;
    }    
    mintMultiple(guids.length, recipient);
  }

  function isValidAccessMessage(MintMethods mintMethod,uint256 messageBoardingGroup, string memory guid,address _addr, bytes memory signature)  public view returns (bool){
    bytes32 hash = keccak256(abi.encodePacked(uint(mintMethod), messageBoardingGroup,bytes(guid), contractIdentifier,_addr));
    return _signingAddress == hash.toEthSignedMessageHash().recover(signature);
  }

  function purchaseToken(uint256 purchaseCount) external payable{
    //Checking to make sure we're not minting before the start time
    require(mintStartTime <= block.timestamp, ConstantsAF.mintBeforeStart_e);
    //Checking if main sale has ended
    require(totalSupply() < 9000, ConstantsAF.mainSaleEnded_e);
    //Checking if correct amount sent
    require(msg.value == priceWEI * purchaseCount, ConstantsAF.incorrectAmount_e);
    //Checking if purchaseCount is under or equals 10
    require(purchaseCount <= 10, ConstantsAF.purchaseTooMany_e);

    mintMultiple(purchaseCount, msg.sender);
  }

  function mintMultiple(uint256 quantity, address targetAddress) private {
    for(uint256 index = 0; index < quantity; index++){
      //Selecting random character
      uint256 characterID = afCharacter.takeRandomCharacter();
      
      // Calculating minted card information
      uint256 specialSauceCode = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));

      // Setting serial numerator
      uint256 serial_numerator = afCharacter.getCharacterSupply(characterID);

      // Performing the mint
      uint256 total = totalSupply();
      uint256 _id = total + 1;
      _safeMint(targetAddress, _id);

      // Recording the minted card
      MintedCard storage card = mintedCards[_id];
      card.characterID = characterID;
      card.specialSauceCode = specialSauceCode;
      card.serial_numerator = serial_numerator;
      // Delete variables
      delete serial_numerator;
      delete specialSauceCode;
      delete characterID;
      delete total;
    }
  }

  function setContractIdentifier(address addr) external onlyEditor{
    contractIdentifier = addr;
  }

  function setBoardingGroup(uint256 newBoardingGroup) external onlyEditor{
    boardingGroup = newBoardingGroup;
  }

  function getCard(uint256 cardID) view external returns (MintedCard memory){
    return mintedCards[cardID];
  }

  function setBaseURI(string memory uri) external onlyEditor{
    customBaseURI = uri;
  }

  function setMintStart(uint256 newMintStartTime) public onlyEditor{
    mintStartTime = newMintStartTime;
  }

  function setPrice(uint256 price) external onlyEditor{
    priceWEI = price;
  }


  function setLicenseURI(string memory uri) external onlyEditor{
    licenseAgreementURI = uri;
  }

  function setRoyaltyTarget(address targetAddress) external onlyEditor{
    royaltyTarget = targetAddress;
  }

  function mintSpecialCharacter(uint256 characterID, address targetAddress) external onlyEditor {
    // Performing the mint
    uint256 _id = totalSupply() + 1;
    _safeMint(targetAddress, _id);

    // Recording the minted card
    MintedCard storage card = mintedCards[_id];
    card.characterID = characterID;
    card.specialSauceCode = 0;
    card.serial_numerator = 1;
  }
}
