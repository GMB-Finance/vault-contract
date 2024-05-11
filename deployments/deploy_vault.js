async function main() {
    const HelloWorld = await ethers.getContractFactory("Vault");
    const hello_world = await HelloWorld.deploy("0x64358a8Dd8AabEb7181be9d4341AC2aD87Fd8bC2", "0xF8Bf82C4eC8bf02909957e5E9e9c298BE9924278","0x64358a8Dd8AabEb7181be9d4341AC2aD87Fd8bC2");
    console.log("Contract Deployed to Address:", hello_world.address);
}
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
