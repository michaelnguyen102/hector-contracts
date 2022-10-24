// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

interface IOwnable {
    function owner() external view returns (address);

    function renounceManagement(string memory confirm) external;

    function pushManagement( address newOwner_ ) external;

    function pullManagement() external;
}

contract Ownable is IOwnable {

    address internal _owner;
    address internal _newOwner;

    event OwnershipPushed(address indexed previousOwner, address indexed newOwner);
    event OwnershipPulled(address indexed previousOwner, address indexed newOwner);

    constructor () {
        _owner = msg.sender;
        emit OwnershipPulled( address(0), _owner );
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require( _owner == msg.sender, "Ownable: caller is not the owner" );
        _;
    }

    function renounceManagement(string memory confirm) public virtual override onlyOwner() {
        require(
            keccak256(abi.encodePacked(confirm)) == keccak256(abi.encodePacked("confirm renounce")),
            "Ownable: renouce needs 'confirm renounce' as input"
        );
        emit OwnershipPushed( _owner, address(0) );
        _owner = address(0);
        _newOwner = address(0);
    }

    function pushManagement( address newOwner_ ) public virtual override onlyOwner() {
        require( newOwner_ != address(0), "Ownable: new owner is the zero address");
        emit OwnershipPushed( _owner, newOwner_ );
        _newOwner = newOwner_;
    }

    function pullManagement() public virtual override {
        require( msg.sender == _newOwner, "Ownable: must be new owner to pull");
        emit OwnershipPulled( _owner, _newOwner );
        _owner = _newOwner;
    }
}


contract BondFeeManagement is Ownable{

    struct BondFeeReceiver {
        address recipient;  //wallet address to receive the fees from bond
        uint feePercentage;    //100%=10000, 40%=4000, 4%=400
        bool isActive;
    }

    mapping(address => BondFeeReceiver[]) public bondReceivers; //bond address => array of fee receipients
    address[] public bondList;  //
    uint MAX_PERCENTAGE_VALUE = 10000;
    uint constant NOT_FOUND = 99999;

    event RegisterBondReceiverEvent(address bondAddress, address recipient, uint feePercentage);
    event UpdateFeePercentageEvent(address bondAddress, address oldRecipient, address recipient, uint oldFees, uint newFees);
    event UpdateRecipientStatusEvent(address bondAddress, address recipient, bool oldValue, bool newValue);
    event AddNewBondRecipientEvent(address bondAddress, address recipient, uint feePercentage);
    event DeleteBondRecipientEvent(address bondAddress, address recipient);
    event DeleteBondEvent(address bondAddress);

    /**
        @notice register receiver to receive fee percentage, weight (100%=10000, 40%=4000, 4%=400)
        @param bondAddress address
        @param recipient address
        @param feePercentage uint
     */
    function registerNewBond(address bondAddress, address recipient, uint feePercentage) external onlyOwner{
        require(bondAddress != address(0), "Invalid bond");
        require(recipient != address(0), "Invalid recipient");
        require(bondExists(bondAddress) == 0, "Bond already exists!");

        uint currentWeightTotal = getTotalFeePercentage(bondAddress);

        require(feePercentage <= MAX_PERCENTAGE_VALUE - currentWeightTotal, "Total percentage must be less than 100%");

        //Check for duplication?
        bondList.push(bondAddress);
   
        bondReceivers[bondAddress].push(BondFeeReceiver(recipient, feePercentage, true));

        emit RegisterBondReceiverEvent(bondAddress, recipient, feePercentage);
    }

     /**
        @notice Update feePercentage for receiver contract (100%=10000, 40%=4000, 4%=400)
        @param bondAddress address
        @param recipient address
        @param feePercentage uint
     */
    function updateFeePercentage(address bondAddress, address recipient, uint feePercentage) external onlyOwner {
        require(bondAddress != address(0), "Invalid bond");
        require(recipient != address(0), "Invalid recipient");
        require(feePercentage > 0, "Must be greater than 0");
         require(bondExists(bondAddress) == 1, "Bond not exists!");

        uint currentWeightTotal = getTotalFeePercentage(bondAddress);
        require(feePercentage <= MAX_PERCENTAGE_VALUE - currentWeightTotal, "Total percentage must be less than 100%");

        uint index =  _findRecipientFromBond(bondAddress, recipient);
        require(index != NOT_FOUND, "Unable to find recipient for the matching bond.");

        uint oldValue = bondReceivers[bondAddress][index].feePercentage;
        address oldRecipient = bondReceivers[bondAddress][index].recipient;
        bool isActive = bondReceivers[bondAddress][index].isActive;

        require(isActive, "Unable to update because recipient is not active!");

        if (isActive) {
            bondReceivers[bondAddress][index].recipient = recipient;
            bondReceivers[bondAddress][index].feePercentage = feePercentage;
            emit UpdateFeePercentageEvent(bondAddress, oldRecipient, recipient, oldValue, feePercentage);
        }
    }

    /**
        @notice Add new recipient to bond contract 
        @param bondAddress address
        @param recipient address
        @param feePercentage uint
     */
    function addNewReceipient(address bondAddress, address recipient, uint feePercentage) external onlyOwner {
        require(bondAddress != address(0), "Invalid bond");
        require(recipient != address(0), "Invalid recipient");
        require(feePercentage > 0, "Must be greater than 0");
        require(bondExists(bondAddress) == 1, "Bond Not Exists! Please register.");

        uint currentWeightTotal = getTotalFeePercentage(bondAddress);
        require(feePercentage <= MAX_PERCENTAGE_VALUE - currentWeightTotal, "Total percentage must be less than 100%");

        bondReceivers[bondAddress].push(BondFeeReceiver(recipient, feePercentage, true));
        emit AddNewBondRecipientEvent(bondAddress, recipient, feePercentage);
    }

    /**
        @notice Delete recipient from bond contract 
        @param bondAddress address
        @param recipient address
     */
    function deleteReceipientFromBond(address bondAddress, address recipient) external onlyOwner {
        require(bondAddress != address(0), "Invalid bond");
        require(recipient != address(0), "Invalid recipient");
        require(bondExists(bondAddress) == 1, "Bond Not Exists! Please register.");

        uint index =  _findRecipientFromBond(bondAddress, recipient);
        require(index != NOT_FOUND, "Unable to find recipient for the matching bond.");

        _deleteBondRecipient(bondAddress, index);
        emit DeleteBondRecipientEvent(bondAddress, recipient);
    }

    /**
        @notice Delete bond contract and all of its recipients
        @param bondAddress address
     */
    function deleteBond(address bondAddress) external onlyOwner {
        require(bondAddress != address(0), "Invalid bond");
        require(bondExists(bondAddress) == 1, "Bond Not Exists! Please register.");

        //Delete all recipients
        delete bondReceivers[bondAddress];
        //Delete bond
        uint index = _findBond(bondAddress);
        _deleteBond(index);

        emit DeleteBondEvent(bondAddress);
    }

    function bondExists(address bond) view internal returns (uint8 exists) {
        uint8 totalBonds = uint8(bondList.length);
        exists = 0; //false

       for(uint i=0;i < totalBonds; i++)  {
            if (bondList[i] == bond) {
                exists = 1;
                break;
            }
       }
    }

    function _findBond(address bond) view internal returns (uint index) {
        index = NOT_FOUND ;

       for(uint i=0;i < bondList.length; i++)  {
            if (bondList[i] == bond) {
                index = i;
                break;
            }
       }
    }

    function _deleteBondRecipient(address bondAddress, uint index) internal {
        BondFeeReceiver[] storage receivers = bondReceivers[bondAddress];
        require(index < receivers.length);
        receivers[index] = receivers[receivers.length-1];
        receivers.pop();
    }

    function _deleteBond(uint index) internal {
        require(index < bondList.length);
        bondList[index] = bondList[bondList.length-1];
        bondList.pop();
    }
            
     function _findRecipientFromBond(address bond, address _recipient) view internal returns (uint index) {
        uint8 totalFeeReceivers = uint8(bondReceivers[bond].length);
        index = NOT_FOUND;

       for(uint i=0;i < totalFeeReceivers; i++)  {
            BondFeeReceiver storage info = bondReceivers[bond][i];
           if (info.recipient == _recipient) {
                index = i;
                break;
           }
       }
    }

    function getTotalFeePercentage(address bond) view internal returns (uint total) {
        uint8 totalFeeReceivers = uint8(bondReceivers[bond].length);
        total = 0;

       for(uint i=0;i < totalFeeReceivers; i++)  {
            BondFeeReceiver storage info = bondReceivers[bond][i];
           if (info.isActive) total += info.feePercentage;
       }
    }

    /**
        @notice Get feePercentage from a receiver contract (100%=10000, 40%=4000, 4%=400)
        @param bondAddress address
        @param recipient address
     */
    function getFeePercentageForRecipient(address bondAddress, address recipient) view external returns(uint feePercentage) {
        feePercentage = 0;
        require(bondAddress != address(0), "Invalid bond");
        require(recipient != address(0), "Invalid recipient");

        uint index =  _findRecipientFromBond(bondAddress, recipient);
        require(index != NOT_FOUND, "Unable to find recipient for the matching bond.");

        bool isActive = bondReceivers[bondAddress][index].isActive;     
        require(isActive, "Unable to update because recipient is not active!");

        if (isActive) {
            feePercentage = bondReceivers[bondAddress][index].feePercentage;
        }
    }

    /**
        @notice Update the active status of the receiver contract
         @param bondAddress address
        @param recipient address
        @param status bool
     */
    function updateRecipientStatus(address bondAddress, address recipient, bool status) external onlyOwner {
        require(bondAddress != address(0), "Invalid bond");
        require(recipient != address(0), "Invalid recipient");

        uint index =  _findRecipientFromBond(bondAddress, recipient);
        require(index != NOT_FOUND, "Unable to find recipient for the matching bond.");

        bool oldValue = bondReceivers[bondAddress][index].isActive; 
        bondReceivers[bondAddress][index].isActive = status;

        emit UpdateRecipientStatusEvent(bondAddress, recipient, oldValue, status);
    }
}
