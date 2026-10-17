// Your business details. The privacy policy, terms and data processing agreement read these, and so do the
// support links inside the app. Fill them in once, then upload this file with the rest of the app.
// (Optional) to point the app at a different Supabase project, add  url: "https://...supabase.co", key: "..."  below.
window.SAAS_CONFIG = {
  business: {
    name: "Luphiwe IT Services",            // the company or person who runs the service
    tradingAs: "Luphiwe LTD",             // what clubs see
    email: "mngqakamba@gmail.com",     // support and privacy requests
    phone: "0832863125 / 0768554189",
    address: "Mswi Street, Phakamisa",
    informationOfficer: "Mthuthuzeli",
    whatsapp: "27832863125"                             // optional, digits only with country code e.g. 27821234567
  },
  // Prices and plan sizes. Change the numbers here and upload this file: no other change needed.
  // maxMembers: null means any number of members.
  billing: {
    currency: "R",
    referencePrefix: "STK",                  // payments are matched by this prefix plus a short club code
    payDays: 7,                              // days an invoice is open for payment
    invoiceNote: "",                         // e.g. "Not VAT registered." or your VAT number
    plans: [
      { id: "small",    name: "Small",    maxMembers: 25,   monthly: 99,  annual: 990 },
      { id: "standard", name: "Standard", maxMembers: 60,   monthly: 199, annual: 1990 },
      { id: "large",    name: "Large",    maxMembers: null, monthly: 349, annual: 3490 }
    ],
    bank: {                                  // shown to clubs and printed on invoices
      accountName: "Mthuthuzeli Ngqakamba",
      bank: "Tymebank",
      accountNumber: "51000058572",
      branchCode: "678910",
      accountType: "Cheque"
    }
  }
};
