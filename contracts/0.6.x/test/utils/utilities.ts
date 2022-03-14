import { Contract } from 'ethers'
import { providers, utils, BigNumber } from 'ethers';
// import {Web3Provider} from providers;
const {
    getAddress,
    keccak256,
    defaultAbiCoder,
    toUtf8Bytes,
    solidityPack
    // @ts-ignore
} = utils;

const PERMIT_TYPEHASH = keccak256(
    toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
)



function getDomainSeparator(name: string, tokenAddress: string) {
    return keccak256(
        defaultAbiCoder.encode(
            ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
            [
                keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
                keccak256(toUtf8Bytes(name)),
                keccak256(toUtf8Bytes('1')),
                1,
                tokenAddress
            ]
        )
    )
}

export function getCreate2Address(
    factoryAddress: string,
    [tokenA, tokenB]: [string, string],
    bytecode: string
): string {
    const [token0, token1] = tokenA < tokenB ? [tokenA, tokenB] : [tokenB, tokenA]
    const create2Inputs = [
        '0xff',
        factoryAddress,
        keccak256(solidityPack(['address', 'address'], [token0, token1])),
        keccak256(bytecode)
    ]
    const sanitizedInputs = `0x${create2Inputs.map(i => i.slice(2)).join('')}`
    return getAddress(`0x${keccak256(sanitizedInputs).slice(-40)}`)
}

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const RewardPerBlock = '7.8375';

// export async function getApprovalDigest(
//     token: Contract,
//     approve: {
//         owner: string
//         spender: string
//         value: BigNumber
//     },
//     nonce: BigNumber,
//     deadline: BigNumber
// ): Promise<string> {
//     const name = await token.name()
//     const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address)
//     return keccak256(
//         solidityPack(
//             ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
//             [
//                 '0x19',
//                 '0x01',
//                 DOMAIN_SEPARATOR,
//                 keccak256(
//                     defaultAbiCoder.encode(
//                         ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
//                         [PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce, deadline]
//                     )
//                 )
//             ]
//         )
//     )
// }

// export async function mineBlock(provider: Web3Provider, timestamp: number): Promise<void> {
//     await new Promise(async (resolve, reject) => {
//         ;(provider._web3Provider.sendAsync as any)(
//             { jsonrpc: '2.0', method: 'evm_mine', params: [timestamp] },
//             (error: any, result: any): void => {
//                 if (error) {
//                     reject(error)
//                 } else {
//                     resolve(result)
//                 }
//             }
//         )
//     })
// }
