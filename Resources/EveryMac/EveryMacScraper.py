import html
import requests
from bs4 import BeautifulSoup
import time
import plistlib
from urllib.parse import urljoin  # Import urljoin

# Define the base URLs for the pages to scrape
base_urls = [
    'https://everymac.com/systems/apple/macbook/',
    'https://everymac.com/systems/apple/macbook-air/',
    'https://everymac.com/systems/apple/macbook_pro/',
    'https://everymac.com/systems/apple/imac/',
    'https://everymac.com/systems/apple/imac-pro/',
    'https://everymac.com/systems/apple/mac_pro/',
    'https://everymac.com/systems/apple/mac_mini/',
    'https://everymac.com/systems/apple/mac-studio/',
]

# Define the global user-agent header
headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'
}

# Function to scrape data from a model page
def scrape_model_page(model_url):
    model_data = {}
    try:
        model_data["Url"] = model_url
        
        response = requests.get(model_url, headers=headers)
        soup = BeautifulSoup(response.text, 'html.parser')

        # Find the div with id="contentcenter"
        contentcenter_div = soup.find('div', id='contentcenter')

        if contentcenter_div:
            # Extract the heading text and clean it
            heading = html.unescape(contentcenter_div.find('h3').text.strip().replace(' Specs', ''))
            model_data["Name"] = heading

            # Find the div with id="macspecs"
            macspecs_div = soup.find('div', id='macspecs')

            # Find all the tables within the div
            tables = macspecs_div.find_all('table')

            for table in tables:
                rows = table.find_all('tr')
                for row in rows:
                    cols = row.find_all('td')
                    if len(cols) >= 2:
                        key = cols[0].text.replace(":", "").strip()
                        value = cols[1].text.strip()
                        model_data[key] = value
                    if len(cols) >= 4:
                        key = cols[2].text.replace(":", "").strip()
                        value = cols[3].text.strip()
                        model_data[key] = value
        assert('Apple Model No' in model_data and 'Model ID' in model_data)
    except Exception as e:
        print(f"Error scraping data for {model_url}: {e}")
        return None

    return model_data

# Main function to fetch data for all years and models
def main():
    years_data = []

    for base_url in base_urls:
        response = requests.get(base_url, headers=headers)
        soup = BeautifulSoup(response.text, 'html.parser')

        # Find all span elements with id starting with "contentcenter_specs_externalnav_2"
        span_elements = soup.find_all('span', id=lambda x: x and x.startswith('contentcenter_specs_externalnav_2'))

        for span_element in span_elements:
            # Check if the span element contains a link
            link = span_element.find('a', href=True)
            if link:
                model_url = urljoin(base_url, link['href'])
                print(f"Scraping data for {model_url}...")
                model_data = scrape_model_page(model_url)
                years_data.append(model_data)
                time.sleep(5)  # Sleep for 5 seconds to avoid overloading the server

    # Save the data to a plist file
    with open('Systems.plist', 'wb') as plist_file:
        plistlib.dump(years_data, plist_file)

if __name__ == "__main__":
    main()
