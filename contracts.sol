// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//add access control 


contract loan is ERC721{
    address public debtor;
    uint256 public apr; 
    address public collectionAddress;
    uint256 public tokenId; 
    bytes32 public uri; 
    uint256 public amntToPay;
    uint256 public endDate; 
    bool public paidOff;
    bool public defaulted; 
    uint256 public nonceForUser; 
    mapping(uint256 => bool) renegotiationByNonce; 

    struct newTermsForSign{
        uint256 newApr;
        uint256 newTimeToPay;
        uint256 newAmntToPay;
    }
    newTermsForSign TermsForSignature; 
    LoanHub HubContract; 
    constructor( 
        string memory name,
        string memory symbol,
        address obligated, 
        uint256  _apr,
        address  _collectionAddress,
        uint256  _tokenId, 
        bytes32  _uri,
        uint256  _amntToPay,
        uint256  _endDate,
        address Hub,
        uint256 nonce
      )ERC721(name, symbol){
        debtor= obligated;
        apr =_apr;
        collectionAddress= _collectionAddress;     
        tokenId= _tokenId;
        uri =_uri; 
        amntToPay= _amntToPay;
        endDate = _endDate; 
        HubContract = LoanHub(Hub);
        nonce = nonceForUser;
      }

      modifier isNotPaidOff(){
          require(paidOff== false || defaulted != true,"this loan has been paid off, don't call this function ");
          _;
      }

      function payBack() payable public isNotPaidOff{
          require(block.timestamp <= endDate, "the period to pay off this loan has ended");
          require(msg.sender == debtor, "don't pay this loan back - you're not the owner");
          amntToPay- msg.value; 
          if(amntToPay == 0){
            returnsToken(collectionAddress, address(HubContract));
            paidOff= true;
          }
      }

      function returnsToken(address _CollectionAddress, address HubContractsAddress) internal{
            ERC721(_CollectionAddress).safeTransferFrom(HubContractsAddress, msg.sender, tokenId); //error seems to be that it needs the placeholder of address this to be traded for sc of the hub 
            HubContract.setLoanAsPaidoff(address(this));
      }

      function submitRequestForRenegotiation(uint256 _apr, uint256 _amntToPay, uint256 timeOfEnding)public isNotPaidOff{
        require(msg.sender == debtor,"you cant renegotiate - you're not the owner");
        newTermsForSign({
            newApr: _apr,
            newTimeToPay: timeOfEnding,
            newAmntToPay: _amntToPay
        });
        HubContract.addRequest(_apr, timeOfEnding, _amntToPay);
      }
      function approveOrRejectRenegotiation(bool accept) public{
        require(msg.sender == address(HubContract),"you cant renegotiate - you're not the owner");
        if(accept == true){
          apr = TermsForSignature.newApr;
          amntToPay = TermsForSignature.newAmntToPay;
          endDate = TermsForSignature.newTimeToPay + block.timestamp;        
        }
      }

      function resolve()public {
          require(msg.sender == address(HubContract),"you cant renegotiate - you're not the owner");
          require(block.timestamp > endDate && paidOff != true && amntToPay ==0,"it's too early or paid off" );
          defaulted= true; 
      }
}

contract LoanHub is ERC721, Ownable{
    //liquidate loan
    //accept offer
 
    struct  ObligationReceipt{
        address collectionAddress;
        uint256 costToPayBack;
        bytes32 uri;
        uint256 apr; 
        uint256 duration; 
        uint256 tokenId;
        uint256 endDate;
        address receiptsAddress; 
        bool paid; 
        uint256 UniqueIdNumber; 
        uint256 loanIdForPerson;
        bool defaulted;
    }

    struct Request{
        uint256 apr; 
        uint256 duration; 
        uint256 amntToPay; 
    }

    address public deployer; 
    uint256 public totalReceipts; 
    mapping(address =>bool) public approvedCollections;
    mapping(address =>bool) public approvedERC20s;
    mapping(address => ObligationReceipt) public receiptFindingViaAddress; 
    // mapping(address=> mapping(uint256  => bool)) personNonceAndUsage; // assign nonce for person and use as true
    mapping(address => uint256) personNonce; 
    mapping(address => Request) listOfNegotiationRequests; 

     constructor( 
        string memory name,
        string memory symbol
      )ERC721(name, symbol){
          deployer = msg.sender; 
      }
     function onERC721Received(
       address ,
       address from,
       uint256 tokenId,
       bytes calldata data
    ) external pure returns (bytes4){
      require(from == address(0x0), "Cannot send tokens directly");
      return IERC721Receiver.onERC721Received.selector;
    }

    function approveCollection(address _CollectionAddress) public{
        approvedCollections[_CollectionAddress]= true;
    }
    function approveERC20(address _erc20Address)public {
            approvedERC20s[_erc20Address]= true;
    }
    function createAnObligationReceipt(address _CollectionAddress, uint256 _tokenId, uint256 _lengthOfLoan, uint256 _apr, string memory nameOfReceipt, string memory symbol)public{ 
        uint256 calculation = calculateLoan(_CollectionAddress, _tokenId,  _lengthOfLoan, _apr); //maybe replace this with the calculation as param from lambda 
        ERC721(_CollectionAddress).safeTransferFrom(msg.sender, address(this), _tokenId);
        bytes32 uriForToken= keccak256(abi.encodePacked(ERC721(_CollectionAddress).tokenURI(_tokenId)));
        ERC721(_CollectionAddress).setApprovalForAll(address(this), true);// - add approval automation in another function
        personNonce[msg.sender]++;
        loan Loans = new loan(nameOfReceipt, symbol, msg.sender, _apr, _CollectionAddress, _tokenId, uriForToken, calculation, block.timestamp + _lengthOfLoan, address(this), personNonce[msg.sender]);// call nameOfReceipt - receipt for 0x..... for collection.......... id.......... 
        totalReceipts++; 
        (payable(address(msg.sender))).transfer(calculation); 
        ObligationReceipt memory receiptRecord = ObligationReceipt({
             collectionAddress: _CollectionAddress,
             costToPayBack: calculation,
             uri: uriForToken,
             apr: _apr, 
             duration: _lengthOfLoan, 
             tokenId: _tokenId,
             endDate: block.timestamp + _lengthOfLoan,
             receiptsAddress: address(Loans),
             paid: false, 
             UniqueIdNumber: totalReceipts,
             loanIdForPerson: personNonce[msg.sender],
             defaulted: false
        });
        receiptFindingViaAddress[address(Loans)]= receiptRecord;
    }
    function calculateLoan(address _CollectionAddress, uint256 _tokenId, uint256 _lengthOfLoan, uint256 _apr) public view returns(uint256 amountForLoan){
        require(approvedCollections[_CollectionAddress]== true, "this collection is not approved");
        require(ERC721(_CollectionAddress).ownerOf(_tokenId)==msg.sender || ERC721(_CollectionAddress).ownerOf(_tokenId)==address(this), "this isn't your token");
        require(_lengthOfLoan >0, "this loan must be longer");
        require(_apr >0, "this loan needs a greater apr");

        //average collection price x # multiplier for trait rarity or amnt in wei an add  x trait rarity multiplier for each thing and offer that amnt in eth // use tokens id with token id api 
        return amountForLoan; 
    }//use opensea apis to calculate 
    function addRequest( uint256 _apr,uint256 timeOfEnding,uint256 _amntToPay) public {
          Request memory listOfRequests  = Request({
                apr: _apr,
                duration: timeOfEnding,
                amntToPay: _amntToPay
            });
        listOfNegotiationRequests[msg.sender] = listOfRequests;
    }
    function acceptOrRejectRenegotiations(address receiptAddress, bool accept) public onlyOwner{
        loan(receiptAddress).approveOrRejectRenegotiation(accept);
    }
    function setLoanAsPaidoff(address receiptsAddress) public  {
        require( deployer== msg.sender || msg.sender ==receiptsAddress );
        ObligationReceipt storage refToReceipt = receiptFindingViaAddress[receiptsAddress];
        refToReceipt.paid = true; 
    }
    function defaultOnLoan(address receiptAddress) public onlyOwner {
        ObligationReceipt storage refToReceipt = receiptFindingViaAddress[receiptAddress];
        require(block.timestamp>refToReceipt.endDate, "Its too early to close the loan");
        refToReceipt.defaulted =true;
        loan(receiptAddress).resolve; 
    }
   
}

//add checks for validity of loan id 



//these processes end with calling the parent contract and changing certain properties or the local contract and then interacting with the parent contract 
//2)pay back loan
//3)liquidate loan
//4)cancel loan
//5) view how nftfi creates obligation receipts 





// what the contract needs to model

   //calculation for loan[x]
    //sign loan with digital signature[]
    //implement loan for person map address to mapping of uint to struct w/ address[x]
    //this creates an obligation receipt with the nft's base uri, apr, and length of loan etc[]
    //erc20 is minted to user from the contracts bank [x]
    //collateral is stored in the obligation receipt[]
    //list of loans by number[x]
    //creates process for creating a loan[]

//1) user starts loan
//2) checks if nft can be deposited- owner checks, is the collections wallet address/name valid?, are you allowed?
//3) calculate loan using elements from nft and opensea api
//4) renegotiate 
//5) accept loan 
//6) signatures 
//7) deposit erc20s
//8) loan id for user and in general- store in mapping 
//9) receive collateral
//10) receive erc20s 
//11) liquidate loan
//12) resolve loan
//13) obligation receipt 
//14) cancel loan











import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BOTZnft is ERC721, ERC721Enumerable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("MyToken", "MTK") {}

    function safeMint(address to) public  {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual         override(ERC721) {
        _transfer(from, to, tokenId);
        _beforeTokenTransfer(from, to, tokenId);
        // require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    
}