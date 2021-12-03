// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.9;

interface IAFCharacter {
  function takeRandomCharacter() external returns (uint256);
  function getCharacterSupply (uint256 characterID) external view returns (uint256);
}
