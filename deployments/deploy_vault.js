async function main() {
    const HelloWorld = await ethers.getContractFactory("Vault");
    const hello_world = await HelloWorld.deploy("0x64358a8Dd8AabEb7181be9d4341AC2aD87Fd8bC2", "0x0F80519Cb8eD3c8360519e25fFDe706762a7B189","0x64358a8Dd8AabEb7181be9d4341AC2aD87Fd8bC2");
    console.log("Contract Deployed to Address:", hello_world.address);
}
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
